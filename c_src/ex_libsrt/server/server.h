#pragma once

#include <srt/srt.h>
#include <string>
#include <memory>
#include <thread>
#include <atomic>
#include <functional>

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

    void Run(const char *address, int port);
    void Stop();
    void CloseConnection(int connection_id);

    void SetOnSocketConnected(std::function<void(SrtSocket)> on_socket_connected) {
        this->on_socket_connected = std::move(on_socket_connected);
    };

    void SetOnSocketDisconnected(std::function<void(SrtSocket)>&& on_socket_disconnected) {
        this->on_socket_disconnected = std::move(on_socket_disconnected);
    }

    void SetOnSocketData(std::function<void(SrtSocket, const char*, int)>&& on_socket_data) {
        this->on_socket_data = std::move(on_socket_data);
    }

    void SetOnFatalError(std::function<void(const std::string&)>&& on_fatal_error) {
        this->on_fatal_error = std::move(on_fatal_error);
    }


private:
    bool IsListeningSocket(SrtSocket socket) const;
    bool IsSocketBroken(SrtSocket socket) const;
    bool IsSocketClosed(SrtSocket socket) const;

    void ReadSocketData(SrtSocket socket);
    void DisconnectSocket(SrtSocket socket);

    void AcceptConnection();

    void RunEpoll();

    void OnNewConnection(
        void* opaque, 
        SRTSOCKET ns, 
        int hsversion,  
        const struct sockaddr* peeraddr, 
        const char* streamid
    );

private:
    SrtSocket srt_sock;
    SrtSocket srt_bind_sock;


    std::atomic_bool running;
    SrtEpoll epoll;
    std::thread epoll_loop;

private:
    std::function<void(SrtSocket)> on_socket_connected;
    std::function<void(SrtSocket)> on_socket_disconnected;
    std::function<void(SrtSocket, const char*, int)> on_socket_data;
    std::function<void(const std::string&)> on_fatal_error;
};
