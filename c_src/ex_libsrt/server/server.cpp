#include "server.h"

#include <chrono>
#include <cstring>
#include <exception>
#include <string>
#include <vector>

#include <unifex/unifex.h>

void Server::Run(const std::string& address,
                 int port,
                 const std::string& password,
                 int latency_ms,
                 int rcvbuf,
                 int udp_rcvbuf,
                 int sndbuf,
                 int udp_sndbuf,
                 int sndtimeo) {
  this->password = password;
  this->latency_ms = latency_ms;
  this->sndtimeo = sndtimeo;

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
  srt_setsockflag(srt_sock, SRTO_SNDSYN, &no, sizeof yes);
  srt_setsockflag(srt_sock, SRTO_STREAMID, &yes, sizeof yes);

  if (latency_ms >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_LATENCY, &latency_ms,
                        sizeof latency_ms) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (rcvbuf >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_RCVBUF, &rcvbuf, sizeof rcvbuf) ==
        SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (udp_rcvbuf >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_UDP_RCVBUF, &udp_rcvbuf,
                        sizeof udp_rcvbuf) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (sndbuf >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_SNDBUF, &sndbuf, sizeof sndbuf) ==
        SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (udp_sndbuf >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_UDP_SNDBUF, &udp_sndbuf,
                        sizeof udp_sndbuf) == SRT_ERROR) {
      throw std::runtime_error(std::string(srt_getlasterror_str()));
    }
  }

  if (sndtimeo >= 0) {
    if (srt_setsockflag(srt_sock, SRTO_SNDTIMEO, &sndtimeo, sizeof sndtimeo) ==
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

  sender_epoll = srt_epoll_create();
  if (sender_epoll == SRT_ERROR) {
    throw std::runtime_error(std::string(srt_getlasterror_str()));
  }

  const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
  srt_epoll_add_usock(epoll, srt_sock, &read_modes);

  running.store(true);
  telemetry_last_emit = std::chrono::steady_clock::now();
  telemetry_last_drained_total = telemetry_drained_bytes_total.load();

  epoll_loop = std::thread(&Server::RunEpoll, this);
  sender_loop = std::thread(&Server::RunSender, this);
}

std::unique_ptr<SrtSocketStats> Server::ReadSocketStats(int socket,
                                                        bool clear_intervals) {
  {
    std::lock_guard<std::mutex> lock(sockets_mutex);
    if (active_sockets.find(socket) == std::end(active_sockets)) {
      return nullptr;
    }
  }

  return readSrtSocketStats(socket, clear_intervals);
}

void Server::Stop() {
  if (running.exchange(false)) {
    send_cv.notify_all();

    if (epoll_loop.joinable()) {
      epoll_loop.join();
    }

    if (sender_loop.joinable()) {
      sender_loop.join();
    }
  }

  if (sender_epoll != -1) {
    srt_epoll_release(sender_epoll);
    sender_epoll = -1;
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

void Server::CloseConnection(int connection_id) { DisconnectSocket(connection_id); }

Server::EnqueueResult Server::EnqueueData(SrtSocket connection_id,
                                          std::unique_ptr<char[]> data,
                                          int len) {
  if (len <= 0 || !data) {
    return EnqueueResult::InvalidPayload;
  }

  if (!running.load()) {
    return EnqueueResult::SocketClosed;
  }

  std::lock_guard<std::mutex> lock(send_mutex);
  auto it = send_queues.find(connection_id);
  if (it == send_queues.end()) {
    return EnqueueResult::SocketNotFound;
  }

  auto& q = it->second;
  if (q.queue.size() >= max_pending_messages_per_conn ||
      q.queued_bytes + static_cast<uint64_t>(len) >
          max_pending_bytes_per_conn) {
    telemetry_enqueue_drops.fetch_add(1);
    return EnqueueResult::WouldBlock;
  }

  q.queue.push_back(PendingMessage{std::move(data), len});
  q.queued_bytes += static_cast<uint64_t>(len);
  telemetry_queue_depth_bytes.fetch_add(static_cast<uint64_t>(len));

  if (!q.out_enabled) {
    const int write_modes = SRT_EPOLL_OUT | SRT_EPOLL_ERR;
    if (srt_epoll_update_usock(sender_epoll, connection_id, &write_modes) !=
        SRT_ERROR) {
      q.out_enabled = true;
    }
  }

  send_cv.notify_one();
  return EnqueueResult::Ok;
}

void Server::RunEpoll() {
  srt_epoll_set(epoll, SRT_EPOLL_ENABLE_EMPTY);

  int sockets_len = 100;
  std::vector<SrtSocket> sockets(static_cast<size_t>(sockets_len));

  int broken_sockets_len = 100;
  std::vector<SrtSocket> broken_sockets(static_cast<size_t>(broken_sockets_len));

  while (running.load()) {
    sockets_len = 100;
    broken_sockets_len = 100;

    int n = srt_epoll_wait(epoll, sockets.data(), &sockets_len,
                           broken_sockets.data(), &broken_sockets_len, 1000, 0,
                           0, 0, 0);

    if (n < 1) {
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

void Server::RunSender() {
  srt_epoll_set(sender_epoll, SRT_EPOLL_ENABLE_EMPTY);

  while (running.load()) {
    int read_len = 128;
    int write_len = 128;
    SrtSocket read_sockets[128];
    SrtSocket write_sockets[128];

    int n = srt_epoll_wait(sender_epoll, read_sockets, &read_len, write_sockets,
                           &write_len, 200, 0, 0, 0, 0);

    if (n < 0) {
      srt_clearlasterror();
      MaybeEmitSendTelemetry();
      continue;
    }

    for (int i = 0; i < read_len; ++i) {
      auto state = srt_getsockstate(read_sockets[i]);
      if (state == SRTS_CLOSED || state == SRTS_BROKEN) {
        DisconnectSocket(read_sockets[i]);
      }
    }

    for (int i = 0; i < write_len; ++i) {
      DrainSendQueue(write_sockets[i]);
    }

    MaybeEmitSendTelemetry();
  }

  MaybeEmitSendTelemetry(true);
}

void Server::DrainSendQueue(SrtSocket socket) {
  while (running.load()) {
    PendingMessage msg;

    {
      std::lock_guard<std::mutex> lock(send_mutex);
      auto qit = send_queues.find(socket);
      if (qit == send_queues.end()) {
        return;
      }

      auto& q = qit->second;
      if (q.queue.empty()) {
        if (q.out_enabled) {
          const int err_modes = SRT_EPOLL_ERR;
          if (srt_epoll_update_usock(sender_epoll, socket, &err_modes) !=
              SRT_ERROR) {
            q.out_enabled = false;
          }
        }
        return;
      }

      msg = std::move(q.queue.front());
      q.queue.pop_front();
      q.queued_bytes -= static_cast<uint64_t>(msg.len);
      telemetry_queue_depth_bytes.fetch_sub(static_cast<uint64_t>(msg.len));
    }

    int sent = srt_sendmsg(socket, msg.data.get(), msg.len, -1, 0);
    if (sent == SRT_ERROR) {
      int err = srt_getlasterror(nullptr);

      if (err == SRT_EASYNCSND || err == SRT_ETIMEOUT) {
        telemetry_send_retries.fetch_add(1);

        std::lock_guard<std::mutex> lock(send_mutex);
        auto qit = send_queues.find(socket);
        if (qit != send_queues.end()) {
          auto& q = qit->second;
          q.queue.push_front(std::move(msg));
          q.queued_bytes += static_cast<uint64_t>(q.queue.front().len);
          telemetry_queue_depth_bytes.fetch_add(
              static_cast<uint64_t>(q.queue.front().len));
          if (!q.out_enabled) {
            const int write_modes = SRT_EPOLL_OUT | SRT_EPOLL_ERR;
            if (srt_epoll_update_usock(sender_epoll, socket, &write_modes) !=
                SRT_ERROR) {
              q.out_enabled = true;
            }
          }
        }

        return;
      }

      auto state = srt_getsockstate(socket);
      if (state == SRTS_CLOSED || state == SRTS_BROKEN) {
        DisconnectSocket(socket);
        return;
      }

      telemetry_enqueue_drops.fetch_add(1);
      continue;
    }

    telemetry_drained_bytes_total.fetch_add(static_cast<uint64_t>(sent));
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

  int no = 0;
  srt_setsockflag(ns, SRTO_SNDSYN, &no, sizeof no);

  if (!password.empty()) {
    srt_setsockflag(ns, SRTO_PASSPHRASE, password.c_str(), password.length());
  }
  if (latency_ms >= 0) {
    srt_setsockflag(ns, SRTO_LATENCY, &latency_ms, sizeof latency_ms);
  }
  if (sndtimeo >= 0) {
    srt_setsockflag(ns, SRTO_SNDTIMEO, &sndtimeo, sizeof sndtimeo);
  }

  std::unique_lock<std::mutex> lock(accept_mutex);

  awaiting_connect_request_socket = ns;

  this->on_connect_request(address, streamid);

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
  bool should_notify = false;

  {
    std::lock_guard<std::mutex> lock(sockets_mutex);
    if (active_sockets.erase(socket) > 0) {
      should_notify = true;
    }
  }

  {
    std::lock_guard<std::mutex> lock(send_mutex);
    auto qit = send_queues.find(socket);
    if (qit != send_queues.end()) {
      telemetry_queue_depth_bytes.fetch_sub(qit->second.queued_bytes);
      send_queues.erase(qit);
    }
  }

  if (epoll != -1) {
    srt_epoll_remove_usock(epoll, socket);
  }

  if (sender_epoll != -1) {
    srt_epoll_remove_usock(sender_epoll, socket);
  }

  if (socket != -1) {
    srt_close(socket);
  }

  if (should_notify) {
    this->on_socket_disconnected(socket);
  }
}

void Server::ReadSocketData(Server::SrtSocket socket) {
  char batch_buf[max_read_per_cycle * 1500];
  int batch_len = 0;

  for (int i = 0; i < max_read_per_cycle; ++i) {
    int n = srt_recv(socket, batch_buf + batch_len, sizeof(batch_buf) - batch_len);

    if (n == SRT_ERROR) {
      if (srt_getlasterror(nullptr) == SRT_EASYNCRCV) {
        break;
      }

      if (batch_len == 0) {
        DisconnectSocket(socket);
        return;
      }

      break;
    }

    if (n == 0) {
      break;
    }

    batch_len += n;
  }

  if (batch_len == 0) {
    DisconnectSocket(socket);
  } else {
    this->on_socket_data(socket, batch_buf, batch_len);
  }
}

void Server::AcceptConnection() {
  struct sockaddr_storage their_addr;
  int addr_len = sizeof their_addr;

  int socket = srt_accept(srt_sock, (struct sockaddr*)&their_addr, &addr_len);
  if (socket == -1) {
    throw std::runtime_error("Failed to accept new socket");
  }

  char raw_streamid[512] = {0};
  int max_streamid_len = 512;
  srt_getsockopt(socket, 0, SRTO_STREAMID, raw_streamid, &max_streamid_len);

  auto streamid = std::string(raw_streamid, raw_streamid + max_streamid_len);

  {
    std::lock_guard<std::mutex> lock(sockets_mutex);
    active_sockets.insert(socket);
  }

  {
    std::lock_guard<std::mutex> lock(send_mutex);
    send_queues.emplace(socket, ConnectionQueue{});
  }

  const int read_modes = SRT_EPOLL_IN | SRT_EPOLL_ERR;
  srt_epoll_add_usock(epoll, socket, &read_modes);

  const int sender_modes = SRT_EPOLL_ERR;
  srt_epoll_add_usock(sender_epoll, socket, &sender_modes);

  this->on_socket_connected(socket, streamid);
}

void Server::MaybeEmitSendTelemetry(bool force) {
  if (!on_send_telemetry) {
    return;
  }

  auto now = std::chrono::steady_clock::now();
  if (!force && now - telemetry_last_emit < std::chrono::seconds(1)) {
    return;
  }

  auto drained_total = telemetry_drained_bytes_total.load();
  auto elapsed_ms = std::chrono::duration_cast<std::chrono::milliseconds>(
                        now - telemetry_last_emit)
                        .count();
  if (elapsed_ms <= 0) {
    elapsed_ms = 1;
  }

  uint64_t drained_delta = drained_total - telemetry_last_drained_total;
  uint64_t drain_rate_bps = drained_delta * 8ULL * 1000ULL /
                            static_cast<uint64_t>(elapsed_ms);

  SendTelemetry telemetry;
  telemetry.queue_depth_bytes = telemetry_queue_depth_bytes.load();
  telemetry.enqueue_drops = telemetry_enqueue_drops.load();
  telemetry.send_retries = telemetry_send_retries.load();
  telemetry.drain_rate_bps = drain_rate_bps;

  telemetry_last_drained_total = drained_total;
  telemetry_last_emit = now;

  on_send_telemetry(telemetry);
}
