#pragma once

#include "server/server.h"
#include "client/client.h"
#include <memory>
#include <unifex/unifex.h>

typedef struct SRTState {
  UnifexPid owner;
  UnifexEnv* env;
  std::unique_ptr<Server> server;
  std::unique_ptr<Client> client;
} State;

#include "_generated/srt_nif.h"
