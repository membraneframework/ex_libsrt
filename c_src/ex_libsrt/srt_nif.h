#pragma once

#include "client/client.h"
#include "server/server.h"
#include <memory>
#include <shared_mutex>
#include <unifex/unifex.h>
#include <unordered_map>

typedef struct SRTState {
  UnifexPid owner;
  UnifexEnv* env;
  std::unordered_map<int, UnifexPid> conn_receivers;
  std::unordered_map<std::string, UnifexPid> stream_id_to_receiver_map;
  std::shared_mutex conn_receivers_mutex;
  std::unique_ptr<Server> server;
  std::unique_ptr<Client> client;
} State;

#include "_generated/srt_nif.h"
