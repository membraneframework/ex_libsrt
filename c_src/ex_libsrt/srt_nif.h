#pragma once

#include "client/client.h"
#include "server/server.h"
#include <memory>
#include <mutex>
#include <unifex/unifex.h>
#include <unordered_map>

typedef struct SRTState {
  UnifexPid owner;
  UnifexEnv* env;
  std::unordered_map<int, UnifexPid> conn_receivers;
  std::mutex conn_receivers_mutex;
  // The server's callbacks run on the epoll thread, libsrt's listener thread and NIF
  // threads, all sending on env; unifex_send is not thread-safe on one env. The
  // client's callbacks only run on its epoll thread, so they don't take this.
  std::mutex send_mutex;
  std::unique_ptr<Server> server;
  std::unique_ptr<Client> client;
} State;

#include "_generated/srt_nif.h"
