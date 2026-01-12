#include "server.h"

#include <chrono>
#include <exception>
#include <string>
#include <unifex/unifex.h>

void Server::Run(const std::string& address,
                 int port,
                 const std::string& password,
                 int latency_ms) {
  this->password = password;
  this->latency_ms = latency_ms;
  
  srt_sock = srt_create_socket();
  if (srt_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  struct sockaddr_in sa;
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);
  if (inet_pton(AF_INET, address.c_str(), &(sa).sin_addr) != 1) {
    throw std::runtime_error("Failed to parse server address");
  }

  int yes = 1;
  int no = 0;
  srt_setsockflag(srt_sock, SRTO_RCVSYN, &no, sizeof yes);
  srt_setsockflag(srt_sock, SRTO_STREAMID, &yes, sizeof yes);
  if (latency_ms >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_LATENCY, &latency_ms, sizeof latency_ms) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  srt_bind_sock = srt_bind(srt_sock, (struct sockaddr*)&(sa), sizeof sa);
  if (srt_bind_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  srt_listen_callback(srt_sock,
                      (srt_listen_callback_fn*)&Server::ListenAcceptCallback,
                      (void*)this);
  srt_bind_sock = srt_listen(srt_sock, MAX_PENDING_CONNECTIONS);
  if (srt_bind_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  epoll = srt_epoll_create();
  if (epoll == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
  srt_epoll_add_usock(epoll, srt_sock, &read_modes);

  running.store(true);

  epoll_loop = std::thread(&Server::RunEpoll, this);
}

std::unique_ptr<SrtSocketStats> Server::ReadSocketStats(int socket, bool clear_intervals) {
  if (active_sockets.find(socket) != std::end(active_sockets)) {
    return readSrtSocketStats(socket, clear_intervals);
  }

  return nullptr;
}

void Server::Stop() {
  if (running.load()) {
    running.store(false);
    epoll_loop.join();
  }

  srt_epoll_release(epoll);
  srt_close(srt_sock);
}

void Server::CloseConnection(int connection_id) {
  if (auto connection = active_sockets.find(connection_id); connection != std::end(active_sockets)) {
    srt_epoll_remove_usock(epoll, connection_id);
    srt_close(connection_id);

    active_sockets.erase(connection_id);
    this->on_socket_disconnected((SrtSocket)connection_id);
  }
}

void Server::RunEpoll() {
  // Setting this one prevents spamming with "no sockets to check, this would deadlock" logs during closing
  // of the system, when there are no sockets in the epoll anymore
  srt_epoll_set(epoll, SRT_EPOLL_ENABLE_EMPTY);

  int sockets_len = 100;
  SrtSocket sockets[sockets_len];

  int broken_sockets_len = 100;
  SrtSocket broken_sockets[broken_sockets_len];

  while (running.load()) {
    sockets_len = 100;
    broken_sockets_len = 100;

    int n = srt_epoll_wait(epoll,
                           &sockets[0],
                           &sockets_len,
                           &broken_sockets[0],
                           &broken_sockets_len,
                           1000,
                           0,
                           0,
                           0,
                           0);

    if (n < 1) {
      // clear out the time out error
      srt_clearlasterror();

      continue;
    }

    for (int i = 0; i < sockets_len; i++) {
      auto socket_state = srt_getsockstate(sockets[i]);

      if (socket_state == SRTS_LISTENING) {
        AcceptConnection();
      } else if (socket_state == SRTS_BROKEN || socket_state == SRTS_CLOSED) {
        DisconnectSocket(sockets[i]);
      } else if (socket_state == SRTS_CONNECTED) {
        ReadSocketData(sockets[i]);
      } else {
        printf("[WARNING] Encountered new socket state, report it to maintainers -> %d\n", socket_state);
      }
    }

    for (int i = 0; i < broken_sockets_len; i++) {
      bool disconnect = true;
      for (int j = 0; j < sockets_len; j++) {
        if (broken_sockets[i] == sockets[j]) {
          disconnect = false;
          break;
        }
      }

      if (disconnect) {
        DisconnectSocket(broken_sockets[i]);
      }
    }
  }
}

int Server::ListenAcceptCallback(void* opaque,
                                 SRTSOCKET ns,
                                 int hsversion,
                                 const sockaddr* peeraddr,
                                 const char* streamid) {
  Server* server = static_cast<Server*>(opaque);
  return server->OnNewConnection(ns, hsversion, peeraddr, streamid);
}

int Server::OnNewConnection(SRTSOCKET ns,
                            int /* hsversion */,
                            const sockaddr* peeraddr,
                            const char* streamid) {
  char ip[INET6_ADDRSTRLEN];

  std::string address;

  if (peeraddr->sa_family == AF_INET) {
    const sockaddr_in* ipv4 = reinterpret_cast<const sockaddr_in*>(peeraddr);

    inet_ntop(AF_INET, &(ipv4->sin_addr), ip, INET_ADDRSTRLEN);

    address = ip;
  } else if (peeraddr->sa_family == AF_INET6) {
    const sockaddr_in6* ipv6 = reinterpret_cast<const sockaddr_in6*>(peeraddr);

    inet_ntop(AF_INET6, &(ipv6->sin6_addr), ip, INET6_ADDRSTRLEN);

    address = ip;
  }

  // Set password if provided
  if (!password.empty()) {
    srt_setsockflag(ns, SRTO_PASSPHRASE, password.c_str(), password.length());
  }
  if (latency_ms >= 0) {
    srt_setsockflag(ns, SRTO_LATENCY, &latency_ms, sizeof latency_ms);
  }

  std::unique_lock<std::mutex> lock(accept_mutex);

  awaiting_connect_request_socket = ns;

  this->on_connect_request(address, streamid);

  // NOTE: this check should be very fast as it blocks any receiving on the socket
  auto result = accept_cv.wait_for(lock, std::chrono::milliseconds(1000));

  if (result == std::cv_status::timeout) {
    srt_setrejectreason(ns, SRT_REJC_PREDEFINED + 504);

    return -1;
  } else if (!accept_awaiting_stream_id) {
    srt_setrejectreason(ns, SRT_REJC_PREDEFINED + 403);

    return -1;
  }

  return 0;
}

void Server::AnswerConnectRequest(int accept) {
  {
    std::lock_guard<std::mutex> lock(accept_mutex);

    accept_awaiting_stream_id = accept;
    awaiting_connect_request_socket = -1;
  }

  accept_cv.notify_one();
}

bool Server::IsListeningSocket(Server::SrtSocket socket) const {
  return socket == srt_sock;
}

bool Server::IsSocketBroken(Server::SrtSocket socket) const {
  return srt_getsockstate(socket) == SRTS_BROKEN;
}

bool Server::IsSocketClosed(Server::SrtSocket socket) const {
  return srt_getsockstate(socket) == SRTS_CLOSED;
}

void Server::DisconnectSocket(Server::SrtSocket socket) {
  srt_epoll_remove_usock(epoll, socket);
  srt_close(socket);

  active_sockets.erase(socket);
  this->on_socket_disconnected(socket);
}

void Server::ReadSocketData(Server::SrtSocket socket) {
  char buffer[1500];

  int n = srt_recv(socket, buffer, sizeof(buffer));

  if (n == 0 || n == SRT_ERROR) {
    DisconnectSocket(socket);
  } else {
    this->on_socket_data(socket, buffer, n);
  }
}

void Server::AcceptConnection() {
  struct sockaddr_storage their_addr;
  int addr_len = sizeof their_addr;

  int socket = srt_accept(srt_sock, (struct sockaddr*)&their_addr, &addr_len);
  if (socket == -1) {
    throw new std::runtime_error("Failed to accept new socket");
  }

  char raw_streamid[512] = {0};
  int max_streamid_len = 512;
  srt_getsockopt(socket, 0, SRTO_STREAMID, raw_streamid, &max_streamid_len);

  auto streamid = std::string(raw_streamid, raw_streamid + max_streamid_len);

  this->on_socket_connected(socket, streamid);
  active_sockets.insert(socket);

  const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
  srt_epoll_add_usock(epoll, socket, &read_modes);
}
