#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <srt/srt.h>
#include <thread>
#include "../common/srt_socket_stats.h"
#include <functional>

class Client {
public:
  using SrtSocket = int;
  using SrtEpoll = int;


  class StreamRejectedException : public std::exception {
  public:
      StreamRejectedException(int code) : message("Stream rejected by server"), code(code) {}

      const char* what() const noexcept override { return message.c_str(); }

      int GetCode() const { return code - SRT_REJC_PREDEFINED; }
  private:
    std::string message;
    int code;
  };
    

  Client(int max_pending_messages, int send_ttl)
      : max_pending_messages(max_pending_messages), send_ttl(send_ttl) {}

  ~Client();

  void Run(const std::string& address,
           int port,
           const std::string& stream_id,
           const std::string& password = "",
           int latency_ms = -1);
  void Send(std::unique_ptr<char[]> data, int len);
  std::unique_ptr<SrtSocketStats> ReadSocketStats(bool clear_intervals);
  void Stop();

  void
  SetOnSocketError(std::function<void(const std::string&)>&& on_socket_error) {
    this->on_socket_error = std::move(on_socket_error);
  }

  void SetOnSocketConnected(std::function<void()>&& on_socket_connected) {
    this->on_socket_connected = std::move(on_socket_connected);
  }

  void SetOnSocketDisconnected(std::function<void()>&& on_socket_disconnected) {
    this->on_socket_disconnected = std::move(on_socket_disconnected);
  }

private:
  void RunEpoll();
  void SendFromQueue();

private:
  SrtSocket srt_sock = -1;
  std::string password;

  std::atomic_bool running;
  SrtEpoll epoll = -1;
  std::thread epoll_loop;

  bool connected = false;

  std::function<void(const std::string&)> on_socket_error;
  std::function<void()> on_socket_connected;
  std::function<void()> on_socket_disconnected;

private:
  const int max_pending_messages;
  const int send_ttl;

  std::mutex send_mutex;
  std::condition_variable send_cv;
  std::deque<std::pair<std::unique_ptr<char[]>, int>> send_queue;
};
