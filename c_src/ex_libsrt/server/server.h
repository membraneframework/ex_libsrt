#pragma once

#include <atomic>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <srt/srt.h>
#include <string>
#include <thread>
#include <set>
#include "../common/srt_socket_stats.h"

extern "C" {
#include <arpa/inet.h>
}

class Server {
  static const int MAX_PENDING_CONNECTIONS = 5;

public:
  using SrtSocket = int;
  using SrtEpoll = int;

  Server() = default;
  ~Server() = default;

  void Run(const std::string& address, int port, const std::string& password = "");

  void Stop();

  void CloseConnection(int connection_id);

  void AnswerConnectRequest(int accept);

  SrtSocket GetAwaitingConnectionRequestId() const { return awaiting_connect_request_socket; }

  std::unique_ptr<SrtSocketStats> ReadSocketStats(int socket, bool clear_intervals);

  void SetOnSocketConnected(
      std::function<void(SrtSocket, const std::string&)> on_socket_connected) {
    this->on_socket_connected = std::move(on_socket_connected);
  };

  void SetOnSocketDisconnected(
      std::function<void(SrtSocket)>&& on_socket_disconnected) {
    this->on_socket_disconnected = std::move(on_socket_disconnected);
  }

  void SetOnSocketData(
      std::function<void(SrtSocket, const char*, int)>&& on_socket_data) {
    this->on_socket_data = std::move(on_socket_data);
  }

  void
  SetOnFatalError(std::function<void(const std::string&)>&& on_fatal_error) {
    this->on_fatal_error = std::move(on_fatal_error);
  }

  void SetOnConnectRequest(
      std::function<void(const std::string&, const std::string&)>&&
          on_connect_request) {
    this->on_connect_request = std::move(on_connect_request);
  }

private:
  bool IsListeningSocket(SrtSocket socket) const;
  bool IsSocketBroken(SrtSocket socket) const;
  bool IsSocketClosed(SrtSocket socket) const;

  void ReadSocketData(SrtSocket socket);
  void DisconnectSocket(SrtSocket socket);

  void AcceptConnection();

  void RunEpoll();

  static int ListenAcceptCallback(void* opaque,
                                  SRTSOCKET ns,
                                  int hsversion,
                                  const struct sockaddr* peeraddr,
                                  const char* streamid);

  int OnNewConnection(SRTSOCKET ns,
                      int hsversion,
                      const struct sockaddr* peeraddr,
                      const char* streamid);

private:
  SrtSocket srt_sock;
  SrtSocket srt_bind_sock;
  std::string password;

  std::atomic_bool running;
  SrtEpoll epoll;
  std::thread epoll_loop;

private:
  std::set<SrtSocket> active_sockets;
  std::function<void(SrtSocket, const std::string&)> on_socket_connected;
  std::function<void(SrtSocket)> on_socket_disconnected;
  std::function<void(SrtSocket, const char*, int)> on_socket_data;
  std::function<void(const std::string&)> on_fatal_error;
  std::function<void(const std::string&, const std::string&)>
      on_connect_request;

  std::mutex accept_mutex;
  std::condition_variable accept_cv;
  bool accept_awaiting_stream_id = false;
  SrtSocket awaiting_connect_request_socket = -1;
};
