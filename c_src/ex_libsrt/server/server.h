#pragma once

#include "../common/srt_socket_stats.h"
#include <atomic>
#include <chrono>
#include <functional>
#include <memory>
#include <mutex>
#include <set>
#include <srt/srt.h>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>

#define BIND_RECEIVER_TIMEOUT_SEC 1

extern "C" {
#include <arpa/inet.h>
}

class Server {
  static const int MAX_PENDING_CONNECTIONS = 100;

public:
  using SrtSocket = int;
  using SrtEpoll = int;

  Server() = default;
  ~Server() = default;

  void Run(const std::string& address,
           int port,
           const std::string& password = "",
           int latency_ms = -1,
           bool accept_all = false,
           std::unordered_set<std::string> stream_ids_whitelist = {});

  void Stop();

  void CloseConnection(int connection_id);

  bool BindSocket(SrtSocket socket, std::string& out_stream_id);

  std::unique_ptr<SrtSocketStats> ReadSocketStats(int socket,
                                                  bool clear_intervals);

  void SetOnSocketDisconnected(
      std::function<void(SrtSocket)>&& on_socket_disconnected) {
    this->on_socket_disconnected = std::move(on_socket_disconnected);
  }

  void SetOnSocketData(
      std::function<void(SrtSocket, const char*, int)> on_socket_data) {
    this->on_socket_data = std::move(on_socket_data);
  }

  void
  SetOnClientRejected(std::function<void(const char*)> on_client_rejected) {
    this->on_client_rejected = on_client_rejected;
  }

  void SetOnClientPending(
      std::function<void(SrtSocket, const std::string&)> on_client_pending) {
    this->on_client_pending = std::move(on_client_pending);
  }

  void SetOnConnectionTimeout(
      std::function<void(SrtSocket, const std::string&)> on_connection_timeout) {
    this->on_connection_timeout = std::move(on_connection_timeout);
  }

  void
  SetOnFatalError(std::function<void(const std::string&)>&& on_fatal_error) {
    this->on_fatal_error = std::move(on_fatal_error);
  }

  void AddStreamIdToWhitelist(std::string stream_id) {
    this->stream_ids_whitelist.insert(stream_id);
  }

  void RemoveStreamIdFromWhitelist(std::string stream_id) {
    this->stream_ids_whitelist.erase(stream_id);
  }

private:
  bool IsListeningSocket(SrtSocket socket) const;
  bool IsSocketBroken(SrtSocket socket) const;
  bool IsSocketClosed(SrtSocket socket) const;

  void ReadSocketData(SrtSocket socket);
  void DisconnectSocket(SrtSocket socket);

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
  int latency_ms = -1;

  std::atomic_bool running;
  SrtEpoll epoll;
  std::thread epoll_loop;

private:
  std::set<SrtSocket> active_sockets;
  std::function<void(SrtSocket)> on_socket_disconnected;
  std::function<void(SrtSocket, const char*, int)> on_socket_data;
  std::function<void(const char*)> on_client_rejected;
  std::function<void(SrtSocket, const std::string&)> on_client_pending;
  std::function<void(SrtSocket, const std::string&)> on_connection_timeout;
  std::function<void(const std::string&)> on_fatal_error;
  bool accept_all = false;
  std::unordered_set<std::string> stream_ids_whitelist = {};

  using PendingEntry =
      std::pair<std::string, std::chrono::steady_clock::time_point>;
  std::unordered_map<SrtSocket, PendingEntry> pending_connections;
  std::mutex pending_mutex;
};
