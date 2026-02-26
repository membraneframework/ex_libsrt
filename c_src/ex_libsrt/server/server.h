#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <set>
#include <srt/srt.h>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "../common/srt_socket_stats.h"

extern "C" {
#include <arpa/inet.h>
}

class Server {
  static const int MAX_PENDING_CONNECTIONS = 5;

 public:
  using SrtSocket = int;
  using SrtEpoll = int;

  struct SendTelemetry {
    uint64_t queue_depth_bytes = 0;
    uint64_t enqueue_drops = 0;
    uint64_t send_retries = 0;
    uint64_t drain_rate_bps = 0;
  };

  struct PendingMessage {
    std::unique_ptr<char[]> data;
    int len;
  };

  enum class EnqueueResult {
    Ok,
    WouldBlock,
    SocketNotFound,
    SocketClosed,
    InvalidPayload,
  };

  Server() = default;
  ~Server() = default;

  void Run(const std::string& address,
           int port,
           const std::string& password = "",
           int latency_ms = -1,
           int rcvbuf = -1,
           int udp_rcvbuf = -1,
           int sndbuf = -1,
           int udp_sndbuf = -1,
           int sndtimeo = -1);

  void Stop();

  void CloseConnection(int connection_id);

  void AnswerConnectRequest(int accept);

  SrtSocket GetAwaitingConnectionRequestId() const {
    return awaiting_connect_request_socket;
  }

  std::unique_ptr<SrtSocketStats> ReadSocketStats(int socket,
                                                  bool clear_intervals);

  EnqueueResult EnqueueData(SrtSocket connection_id,
                            std::unique_ptr<char[]> data,
                            int len);

  EnqueueResult EnqueueBatchData(SrtSocket connection_id,
                                 std::vector<PendingMessage>&& messages,
                                 uint64_t total_bytes);

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

  void SetOnFatalError(std::function<void(const std::string&)>&& on_fatal_error) {
    this->on_fatal_error = std::move(on_fatal_error);
  }

  void SetOnConnectRequest(
      std::function<void(const std::string&, const std::string&)>&&
          on_connect_request) {
    this->on_connect_request = std::move(on_connect_request);
  }

  void SetOnSendTelemetry(
      std::function<void(const SendTelemetry&)>&& on_send_telemetry) {
    this->on_send_telemetry = std::move(on_send_telemetry);
  }

 private:
  struct ConnectionQueue {
    std::deque<PendingMessage> queue;
    uint64_t queued_bytes = 0;
    bool out_enabled = false;
  };

  bool IsListeningSocket(SrtSocket socket) const;
  bool IsSocketBroken(SrtSocket socket) const;
  bool IsSocketClosed(SrtSocket socket) const;

  void ReadSocketData(SrtSocket socket);
  void DisconnectSocket(SrtSocket socket);

  void AcceptConnection();

  void RunEpoll();
  void RunSender();
  void DrainSendQueue(SrtSocket socket);
  void MaybeEmitSendTelemetry(bool force = false);

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
  static constexpr int max_read_per_cycle = 20;
  static constexpr size_t max_pending_messages_per_conn = 4096;
  static constexpr uint64_t max_pending_bytes_per_conn = 64 * 1024 * 1024;

  SrtSocket srt_sock = -1;
  SrtSocket srt_bind_sock = -1;
  std::string password;
  int latency_ms = -1;
  int sndtimeo = -1;

  std::atomic_bool running{false};
  SrtEpoll epoll = -1;
  SrtEpoll sender_epoll = -1;
  std::thread epoll_loop;
  std::thread sender_loop;

  std::mutex sockets_mutex;
  std::set<SrtSocket> active_sockets;

  std::mutex send_mutex;
  std::condition_variable send_cv;
  std::unordered_map<SrtSocket, ConnectionQueue> send_queues;

  std::atomic<uint64_t> telemetry_queue_depth_bytes{0};
  std::atomic<uint64_t> telemetry_enqueue_drops{0};
  std::atomic<uint64_t> telemetry_send_retries{0};
  std::atomic<uint64_t> telemetry_drained_bytes_total{0};
  uint64_t telemetry_last_drained_total = 0;
  std::chrono::steady_clock::time_point telemetry_last_emit;

  std::function<void(SrtSocket, const std::string&)> on_socket_connected;
  std::function<void(SrtSocket)> on_socket_disconnected;
  std::function<void(SrtSocket, const char*, int)> on_socket_data;
  std::function<void(const std::string&)> on_fatal_error;
  std::function<void(const std::string&, const std::string&)> on_connect_request;
  std::function<void(const SendTelemetry&)> on_send_telemetry;

  std::mutex accept_mutex;
  std::condition_variable accept_cv;
  bool accept_awaiting_stream_id = false;
  SrtSocket awaiting_connect_request_socket = -1;
};
