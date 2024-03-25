#include "server.h"

#include <exception>
#include <string>
#include <unifex/unifex.h>

void Server::Initialize(const char* address, int port) {
  srt_sock = srt_create_socket();
  if (srt_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  struct sockaddr_in sa;
  sa.sin_family = AF_INET;
  sa.sin_port = htons(port);
  if (inet_pton(AF_INET, address, &(sa).sin_addr) != 1) {
    throw std::runtime_error("Failed to parse server address");
  }

  int yes = 1;
  int no = 0;
  srt_setsockflag(srt_sock, SRTO_RCVSYN, &no, sizeof yes);
  srt_setsockflag(srt_sock, SRTO_STREAMID, &yes, sizeof yes);

  srt_bind_sock = srt_bind(srt_sock, (struct sockaddr*)&(sa), sizeof sa);
  if (srt_bind_sock == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

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
  

  // TODO: this must be a lambda embedding 'this'
  // srt_listen_callback(srt_socket, &OnNewConnection, NULL);
}

void Server::Run() {
    running.store(true);

    epoll_loop = std::thread(&Server::RunEpoll, this);
}

void Server::Stop() {
  if (running.load()) {
    running.store(false);
    epoll_loop.join();
  }

  srt_close(srt_sock);
}

void Server::CloseConnection(int connection_id) {
  srt_epoll_remove_usock(epoll, connection_id);
  srt_close(connection_id);
}

void Server::RunEpoll() {
   int srtrfdslenmax = 100;
   SrtSocket sockets[srtrfdslenmax];

    while (running.load()) {
      int n = srt_epoll_wait(epoll, &sockets[0], &srtrfdslenmax, 0, 0, 1000, 0, 0, 0, 0); 

      for (int i = 0; i < n; i++) {
        if (IsListeningSocket(sockets[i])) {
          AcceptConnection();
        } else if (IsSocketBroken(sockets[i])) {
          DisconnectSocket(sockets[i]);
        } else if (IsSocketClosed(sockets[i])) {
          DisconnectSocket(sockets[i]);
        } else {
          ReadSocketData(sockets[i]);
        }
      }
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

  this->on_socket_disconnected(socket);
}

void Server::ReadSocketData(Server::SrtSocket socket) {
  char buffer[1500];

  int n = srt_recv(socket, buffer, sizeof(buffer));

  this->on_socket_data(socket, buffer, n);
}

void Server::AcceptConnection() {
  struct sockaddr_storage their_addr;
  int addr_len = sizeof their_addr;

  int socket = srt_accept(srt_sock, (struct sockaddr*)&their_addr, &addr_len);
  if (socket == -1) {
      throw new std::runtime_error("Failed to accept new socket");
  }

  // auto streamid = srt_getsock(socket);

  this->on_socket_connected(socket);

  const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
  srt_epoll_add_usock(epoll, socket, &read_modes);
}
