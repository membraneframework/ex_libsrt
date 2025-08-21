#include "client.h"

#include <exception>
#include <utility>
#include <chrono>

Client::~Client() {
  if (epoll != -1) {
    srt_epoll_release(epoll);
  }

  if (srt_sock != -1) {
    srt_close(srt_sock);
  }
}

void Client::Run(const std::string& address, int port, const std::string& stream_id, const std::string& password) {
  this->password = password;
  
  srt_sock = srt_create_socket();
  if (srt_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  struct sockaddr_in sa;
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);

  if (inet_pton(AF_INET, address.c_str(), &sa.sin_addr) != 1) {
    throw std::runtime_error("Failed to parse server address");
  }

  int yes = 1;
  int no = 0;

  if (srt_setsockflag(srt_sock, SRTO_SENDER, &yes, sizeof yes) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  if (srt_setsockflag(srt_sock, SRTO_SNDSYN, &no, sizeof no) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  if (!stream_id.empty()) {
    if (srt_setsockflag(
            srt_sock, SRTO_STREAMID, stream_id.c_str(), stream_id.length()) ==
        SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  // Set password if provided
  if (!password.empty()) {
    if (srt_setsockflag(srt_sock, SRTO_PASSPHRASE, password.c_str(), password.length()) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  epoll = srt_epoll_create();
  if (epoll == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  const int write_modes = SRT_EPOLL_OUT | SRT_EPOLL_ERR;

  if (srt_epoll_add_usock(epoll, srt_sock, &write_modes) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  int result = srt_connect(srt_sock, (struct sockaddr*)&sa, sizeof sa);
  if (result == SRT_ERROR)  {
    auto code = srt_getrejectreason(srt_sock);

    throw StreamRejectedException(code);
  }

  running.store(true);
  epoll_loop = std::thread(&Client::RunEpoll, this);
}

void Client::Send(std::unique_ptr<char[]> data, int len) {
  if (running.load()) {
    auto lock = std::unique_lock(send_mutex);
    send_cv.wait(lock,
                 [&] { return (int)send_queue.size() < max_pending_messages || running.load(); });

    send_queue.emplace_back(std::move(data), len);
  } else {
    throw std::runtime_error("Client is not active");
  }

  send_cv.notify_all();
}

std::unique_ptr<SrtSocketStats> Client::ReadSocketStats(bool clear_intervals) {
  return readSrtSocketStats(srt_sock, clear_intervals);
}

void Client::Stop() {
  if (running.load()) {
    while (true) {
      auto lock = std::unique_lock(send_mutex);

      send_cv.wait(lock, [&] { return send_queue.empty() || running.load(); });

      if (send_queue.empty() || running.load()) {
        break;
      }
    }

    running.store(false);
    send_cv.notify_all();
  }

  if (epoll_loop.joinable()) {
    epoll_loop.join();
  }

  if (epoll != -1) {
    srt_epoll_release(epoll);

    epoll = -1;
  }

  sleep(1); // workaround to make sure all the packets are sent, as shown here: https://github.com/Haivision/srt/blob/952f9495246abc201bac55b8f9ad7409c0572423/examples/test-c-client.c#L94
  if (srt_sock != -1) {
    srt_close(srt_sock);

    srt_sock = -1;
  }
}

void Client::RunEpoll() {
  try {
    while (running.load()) {
      int read_error_len = 1;
      int read_out_len = 1;
      SrtSocket read_error;
      SrtSocket read_out;

      int n = srt_epoll_wait(epoll,
                             &read_error,
                             &read_error_len,
                             &read_out,
                             &read_out_len,
                             200,
                             0,
                             0,
                             0,
                             0);
      if (n < 0) {
        continue;
      }

      if (read_out_len > 0 && !connected) {
        connected = true;

        if (on_socket_connected) {
          on_socket_connected();
        }
      }

      if (read_error_len > 0 && !connected) {
        int code = srt_getrejectreason(read_error);
        auto reason = srt_rejectreason_str(code);

        throw std::runtime_error(reason);
      }

      if (read_error_len > 0) {
        int posix_err;
        auto code = srt_getlasterror(&posix_err);

        if (code == 0) {
          running.store(false);
          send_cv.notify_all();

          on_socket_disconnected();

          return;
        } else {
          auto reason = srt_getlasterror_str();

          throw std::runtime_error(reason);
        }
      }

      if (read_out_len > 0) {
        auto lock = std::unique_lock(send_mutex);

        auto sendable = send_cv.wait_for(
            lock,
            std::chrono::milliseconds(500),
            [&] { return !this->send_queue.empty() || !running.load(); });

        // we are waiting with timeout to make sure that we catch a socket disconnect event even when blocking
        if (!sendable) {
          continue;
        }

        SendFromQueue();
      }

      send_cv.notify_all();
    }
  } catch (const std::exception& e) {
    running.store(false);
    send_cv.notify_all();

    if (on_socket_error) {
      on_socket_error(e.what());
    }
  }
}

void Client::SendFromQueue() {
  if (send_queue.empty()) {
    return;
  }

  auto [buffer, size] = std::move(send_queue.front());

  send_queue.pop_front();

  if (srt_sendmsg(srt_sock, buffer.get(), size, send_ttl, 0) == SRT_ERROR) {
    auto state = srt_getsockstate(srt_sock);

    if (state == SRTS_CLOSED || state == SRTS_BROKEN) {
      throw std::runtime_error("Socket is closed or broken");
    } else {
      throw std::runtime_error(srt_getlasterror_str());
    }
  }
}
