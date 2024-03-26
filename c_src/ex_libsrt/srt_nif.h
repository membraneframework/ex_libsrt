#pragma once

#include "client/client.h"
#include "server/server.h"
#include <memory>
#include <unifex/unifex.h>

typedef struct SRTState {
  UnifexPid owner;
  UnifexEnv* env;
  std::unique_ptr<Server> server;
  std::unique_ptr<Client> client;
} State;

#include "_generated/srt_nif.h"
