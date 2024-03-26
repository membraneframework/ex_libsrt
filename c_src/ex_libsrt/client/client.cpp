#include "client.h"

#include <exception>
#include <utility>

Client::~Client() {
  if (epoll != -1) {
    srt_epoll_release(epoll);
  }

  if (srt_sock != -1) {
    srt_close(srt_sock);
  }
}

void Client::Run(const char* address, int port, const char* stream_id) {
  srt_sock = srt_create_socket();
  if (srt_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  struct sockaddr_in sa;
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);

  if (inet_pton(AF_INET, address, &sa.sin_addr) != 1) {
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

  epoll = srt_epoll_create();
  if (epoll == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  const int write_modes = SRT_EPOLL_OUT | SRT_EPOLL_ERR;

  if (srt_epoll_add_usock(epoll, srt_sock, &write_modes) == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  int result = srt_connect(srt_sock, (struct sockaddr*)&sa, sizeof sa);
  if (result == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  running.store(true);
  epoll_loop = std::thread(&Client::RunEpoll, this);
}

void Client::Send(std::unique_ptr<char[]> data, int len) {
  if (running.load()) {
    auto lock = std::unique_lock(send_mutex);
    send_cv.wait(lock, [&] { return (int)send_queue.size() < max_pending_messages; });

    send_queue.emplace_back(std::move(data), len);
  } else {
    throw std::runtime_error("Client is not active");
  }

  send_cv.notify_all();
}

void Client::Stop() {
  if (running.load()) {
    while (true) {
      auto lock = std::unique_lock(send_mutex);

      send_cv.wait(lock, [&] { return send_queue.empty(); });

      if (send_queue.empty()) {
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

    if (read_error_len > 0) {
      int code = srt_getrejectreason(read_error);
      auto reason =  srt_rejectreason_str(code);

      throw std::runtime_error(reason);
    }

    if (read_out_len > 0) {
      auto lock = std::unique_lock(send_mutex);

      send_cv.wait(
          lock, [&] { return !this->send_queue.empty() || !running.load(); });

      SendFromQueue();
    }

    send_cv.notify_all();
  }
  } catch (const std::exception& e) {
    running.store(false);

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
