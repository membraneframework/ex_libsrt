#include "client.h"

#include <cstring>
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

void Client::Run(const std::string& address,
                 int port,
                 const std::string& stream_id,
                 const std::string& password,
                 int latency_ms) {
  this->password = password;

  struct sockaddr_storage ss;
  socklen_t ss_len;
  int af;
  memset(&ss, 0, sizeof(ss));

  struct sockaddr_in6 *sa6 = reinterpret_cast<struct sockaddr_in6*>(&ss);
  struct sockaddr_in  *sa4 = reinterpret_cast<struct sockaddr_in*>(&ss);

  if (inet_pton(AF_INET6, address.c_str(), &sa6->sin6_addr) == 1) {
    sa6->sin6_family = AF_INET6;
    sa6->sin6_port = htons(port);
    ss_len = sizeof(struct sockaddr_in6);
    af = AF_INET6;
  } else if (inet_pton(AF_INET, address.c_str(), &sa4->sin_addr) == 1) {
    sa4->sin_family = AF_INET;
    sa4->sin_port = htons(port);
    ss_len = sizeof(struct sockaddr_in);
    af = AF_INET;
  } else {
    throw std::runtime_error("Failed to parse server address: " + address);
  }

  srt_sock = srt_create_socket();
  if (srt_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  int yes = 1;
  int no = 0;

  if (af == AF_INET6) {
    if (srt_setsockflag(srt_sock, SRTO_IPV6ONLY, &yes, sizeof yes) == SRT_ERROR) {
        throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  int sender = sender_mode ? 1 : 0;
  if (srt_setsockflag(srt_sock, SRTO_SENDER, &sender, sizeof sender) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  if (srt_setsockflag(srt_sock, SRTO_SNDSYN, &no, sizeof no) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  if (!sender_mode) {
    if (srt_setsockflag(srt_sock, SRTO_RCVSYN, &no, sizeof no) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (latency_ms >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_LATENCY, &latency_ms, sizeof latency_ms) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
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

  int poll_modes = SRT_EPOLL_OUT | SRT_EPOLL_ERR;

  if (!sender_mode) {
    poll_modes |= SRT_EPOLL_IN;
  }

  if (srt_epoll_add_usock(epoll, srt_sock, &poll_modes) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  int result = srt_connect(srt_sock, reinterpret_cast<struct sockaddr*>(&ss), ss_len);
  if (result == SRT_ERROR)  {
    auto code = srt_getrejectreason(srt_sock);

    throw StreamRejectedException(code);
  }

  running.store(true);
  epoll_loop = std::thread(&Client::RunEpoll, this);
}

void Client::Send(std::unique_ptr<char[]> data, int len) {
  if (!sender_mode) {
    throw std::runtime_error("Client is not in sender mode");
  }

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
  // Setting this one prevents spamming with "no sockets to check, this would deadlock" logs during closing
  // of the system, when there are no sockets in the epoll anymore
  srt_epoll_set(epoll, SRT_EPOLL_ENABLE_EMPTY);

  try {
    while (running.load()) {
      int read_len = 1;
      int write_len = 1;
      SrtSocket read_socket;
      SrtSocket write_socket;

      int n = srt_epoll_wait(epoll,
                             &read_socket,
                             &read_len,
                             &write_socket,
                             &write_len,
                             200,
                             0,
                             0,
                             0,
                             0);
      if (n < 0) {
        // clear out timeout/empty-epoll errors that can happen during teardown
        srt_clearlasterror();

        if (!running.load()) {
          return;
        }

        continue;
      }

      if (write_len > 0 && !connected) {
        connected = true;

        if (on_socket_connected) {
          on_socket_connected();
        }
      }

      if (read_len > 0) {
        auto socket_state = srt_getsockstate(read_socket);

        if (!connected && socket_state == SRTS_BROKEN) {
          int code = srt_getrejectreason(read_socket);
          auto reason = srt_rejectreason_str(code);

          throw std::runtime_error(reason);
        }

        if (socket_state == SRTS_CLOSED || socket_state == SRTS_BROKEN) {
          running.store(false);
          send_cv.notify_all();

          if (connected && on_socket_disconnected) {
            on_socket_disconnected();
          }

          return;
        }

        if (!sender_mode && socket_state == SRTS_CONNECTED) {
          char buffer[1500];

          int bytes_read = srt_recv(read_socket, buffer, sizeof(buffer));

          if (bytes_read == 0 || bytes_read == SRT_ERROR) {
            running.store(false);
            send_cv.notify_all();

            if (on_socket_disconnected) {
              on_socket_disconnected();
            }

            return;
          }

          if (on_socket_data) {
            on_socket_data(buffer, bytes_read);
          }
        }
      }

      if (sender_mode && write_len > 0) {
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
