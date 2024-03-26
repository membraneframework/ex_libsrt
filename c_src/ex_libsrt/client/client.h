#include <atomic>
#include <condition_variable>
#include <deque>
#include <mutex>
#include <srt/srt.h>
#include <thread>

class Client {
public:
  using SrtSocket = int;
  using SrtEpoll = int;

  Client(int max_pending_messages, int send_ttl)
      : max_pending_messages(max_pending_messages), send_ttl(send_ttl) {}

  ~Client();

  void Run(const char* address, int port, const char* stream_id);
  void Send(std::unique_ptr<char[]> data, int len);
  void Stop();

  void
  SetOnSocketError(std::function<void(const std::string&)>&& on_socket_error) {
    this->on_socket_error = std::move(on_socket_error);
  }

  void SetOnSocketConnected(std::function<void()>&& on_socket_connected) {
    this->on_socket_connected = std::move(on_socket_connected);
  }

private:
  void RunEpoll();
  void SendFromQueue();

private:
  SrtSocket srt_sock = -1;

  std::atomic_bool running;
  SrtEpoll epoll = -1;
  std::thread epoll_loop;

  bool connected = false;

  std::function<void(const std::string&)> on_socket_error;
  std::function<void()> on_socket_connected;

private:
  const int max_pending_messages;
  const int send_ttl;

  std::mutex send_mutex;
  std::condition_variable send_cv;
  std::deque<std::pair<std::unique_ptr<char[]>, int>> send_queue;
};