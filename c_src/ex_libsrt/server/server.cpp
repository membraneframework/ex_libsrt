#include "server.h"

#include <cstring>
#include <string>
#include <unifex/unifex.h>
#include <unordered_set>
#include <vector>

void Server::Run(const std::string& address,
                 int port,
                 const std::string& password,
                 int latency_ms,
                 std::unordered_set<std::string> ids_whitelist) {
  this->password = password;
  this->latency_ms = latency_ms;
  this->stream_ids_whitelist = std::move(ids_whitelist);

  struct sockaddr_storage ss;
  socklen_t ss_len;
  int af;
  memset(&ss, 0, sizeof(ss));

  struct sockaddr_in6* sa6 = reinterpret_cast<struct sockaddr_in6*>(&ss);
  struct sockaddr_in* sa4 = reinterpret_cast<struct sockaddr_in*>(&ss);

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
    if (srt_setsockflag(srt_sock, SRTO_IPV6ONLY, &yes, sizeof yes) ==
        SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  srt_setsockflag(srt_sock, SRTO_RCVSYN, &no, sizeof yes);
  srt_setsockflag(srt_sock, SRTO_STREAMID, &yes, sizeof yes);
  if (latency_ms >= 0) {
    if (srt_setsockflag(
            srt_sock, SRTO_LATENCY, &latency_ms, sizeof latency_ms) ==
        SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  srt_bind_sock =
      srt_bind(srt_sock, reinterpret_cast<struct sockaddr*>(&ss), ss_len);
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

std::unique_ptr<SrtSocketStats> Server::ReadSocketStats(int socket,
                                                        bool clear_intervals) {
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
  if (auto connection = active_sockets.find(connection_id);
      connection != std::end(active_sockets)) {
    srt_epoll_remove_usock(epoll, connection_id);
    srt_close(connection_id);

    active_sockets.erase(connection_id);
    this->on_socket_disconnected((SrtSocket)connection_id);
  }
}

void Server::RunEpoll() {
  // Setting this one prevents spamming with "no sockets to check, this would
  // deadlock" logs during closing of the system, when there are no sockets in
  // the epoll anymore
  srt_epoll_set(epoll, SRT_EPOLL_ENABLE_EMPTY);

  int sockets_len = 100;
  std::vector<SrtSocket> sockets(static_cast<size_t>(sockets_len));

  int broken_sockets_len = 100;
  std::vector<SrtSocket> broken_sockets(
      static_cast<size_t>(broken_sockets_len));

  while (running.load()) {
    sockets_len = 100;
    broken_sockets_len = 100;

    int n = srt_epoll_wait(epoll,
                           sockets.data(),
                           &sockets_len,
                           broken_sockets.data(),
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
        // do nothing
      } else if (socket_state == SRTS_BROKEN || socket_state == SRTS_CLOSED) {
        DisconnectSocket(sockets[i]);
      } else if (socket_state == SRTS_CONNECTED) {
        ReadSocketData(sockets[i]);
      } else {
        printf("[WARNING] Encountered new socket state, report it to "
               "maintainers -> %d\n",
               socket_state);
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

  if (stream_ids_whitelist.find(std::string(streamid)) !=
      stream_ids_whitelist.end()) {

    this->on_socket_connected(ns, streamid);
    active_sockets.insert(ns);
    const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
    srt_epoll_add_usock(epoll, ns, &read_modes);

    return 0;
  } else {
    srt_setrejectreason(ns, SRT_REJC_PREDEFINED + 403);

    on_client_rejected(streamid);

    return -1;
  }
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
