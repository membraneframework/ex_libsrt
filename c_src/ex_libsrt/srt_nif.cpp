#include "srt_nif.h"
#include <cstdlib>
#include <thread>
#include <vector>

#include <srt/srt.h>

static void close_all_connections(State* state) {
  if (state->server == nullptr) {
    return;
  }

  std::vector<int> conn_ids;
  {
    std::shared_lock lock(state->conn_receivers_mutex);
    conn_ids.reserve(state->conn_receivers.size());
    for (const auto& entry : state->conn_receivers) {
      conn_ids.push_back(entry.first);
    }
  }

  for (const auto conn_id : conn_ids) {
    state->server->CloseConnection(conn_id);
  }
}

int on_load(UnifexEnv* env, void** priv_data) {
  UNIFEX_UNUSED(env);
  UNIFEX_UNUSED(priv_data);

  srt_startup();

  if (const char* env_p = std::getenv("SRT_LOG_LEVEL")) {
    if (strcmp(env_p, "debug") == 0) {
      srt_setloglevel(srt_logging::LogLevel::debug);
    } else if (strcmp(env_p, "notice") == 0) {
      srt_setloglevel(srt_logging::LogLevel::note);
    } else if (strcmp(env_p, "warning") == 0) {
      srt_setloglevel(srt_logging::LogLevel::warning);
    } else if (strcmp(env_p, "error") == 0) {
      srt_setloglevel(srt_logging::LogLevel::error);
    } else if (strcmp(env_p, "fatal") == 0) {
      srt_setloglevel(srt_logging::LogLevel::fatal);
    }
  } else {
    srt_setloglevel(srt_logging::LogLevel::error);
  }

  return 0;
}

void on_unload(UnifexEnv* env, void* priv_data) {
  UNIFEX_UNUSED(env);
  UNIFEX_UNUSED(priv_data);

  srt_cleanup();
}

void handle_destroy_state(UnifexEnv* env, UnifexState* state) {
  UNIFEX_UNUSED(env);

  if (state->server) {
    state->server->Stop();
  }

  if (state->client) {
    state->client->Stop();
  }

  state->~State();
}

srt_socket_stats map_socket_stats(SrtSocketStats* stats) {
  srt_socket_stats srt_stats;

  srt_stats.msTimeStamp = stats->msTimeStamp;
  srt_stats.pktSentTotal = stats->pktSentTotal;
  srt_stats.pktRecvTotal = stats->pktRecvTotal;
  srt_stats.pktSentUniqueTotal = stats->pktSentUniqueTotal;
  srt_stats.pktRecvUniqueTotal = stats->pktRecvUniqueTotal;
  srt_stats.pktSndLossTotal = stats->pktSndLossTotal;
  srt_stats.pktRcvLossTotal = stats->pktRcvLossTotal;
  srt_stats.pktRetransTotal = stats->pktRetransTotal;
  srt_stats.pktSentACKTotal = stats->pktSentACKTotal;
  srt_stats.pktRecvACKTotal = stats->pktRecvACKTotal;
  srt_stats.pktSentNAKTotal = stats->pktSentNAKTotal;
  srt_stats.pktRecvNAKTotal = stats->pktRecvNAKTotal;
  srt_stats.usSndDurationTotal = stats->usSndDurationTotal;
  srt_stats.pktSndDropTotal = stats->pktSndDropTotal;
  srt_stats.pktRcvDropTotal = stats->pktRcvDropTotal;
  srt_stats.pktRcvUndecryptTotal = stats->pktRcvUndecryptTotal;
  srt_stats.pktSndFilterExtraTotal = stats->pktSndFilterExtraTotal;
  srt_stats.pktRcvFilterExtraTotal = stats->pktRcvFilterExtraTotal;
  srt_stats.pktRcvFilterSupplyTotal = stats->pktRcvFilterSupplyTotal;
  srt_stats.pktRcvFilterLossTotal = stats->pktRcvFilterLossTotal;
  srt_stats.byteSentTotal = stats->byteSentTotal;
  srt_stats.byteRecvTotal = stats->byteRecvTotal;
  srt_stats.byteSentUniqueTotal = stats->byteSentUniqueTotal;
  srt_stats.byteRecvUniqueTotal = stats->byteRecvUniqueTotal;
  srt_stats.byteRcvLossTotal = stats->byteRcvLossTotal;
  srt_stats.byteRetransTotal = stats->byteRetransTotal;
  srt_stats.byteSndDropTotal = stats->byteSndDropTotal;
  srt_stats.byteRcvDropTotal = stats->byteRcvDropTotal;
  srt_stats.byteRcvUndecryptTotal = stats->byteRcvUndecryptTotal;
  srt_stats.pktSent = stats->pktSent;
  srt_stats.pktRecv = stats->pktRecv;
  srt_stats.pktSentUnique = stats->pktSentUnique;
  srt_stats.pktRecvUnique = stats->pktRecvUnique;
  srt_stats.pktSndLoss = stats->pktSndLoss;
  srt_stats.pktRcvLoss = stats->pktRcvLoss;
  srt_stats.pktRetrans = stats->pktRetrans;
  srt_stats.pktRcvRetrans = stats->pktRcvRetrans;
  srt_stats.pktSentACK = stats->pktSentACK;
  srt_stats.pktRecvACK = stats->pktRecvACK;
  srt_stats.pktSentNAK = stats->pktSentNAK;
  srt_stats.pktRecvNAK = stats->pktRecvNAK;
  srt_stats.pktSndFilterExtra = stats->pktSndFilterExtra;
  srt_stats.pktRcvFilterExtra = stats->pktRcvFilterExtra;
  srt_stats.pktRcvFilterSupply = stats->pktRcvFilterSupply;
  srt_stats.pktRcvFilterLoss = stats->pktRcvFilterLoss;
  srt_stats.mbpsSendRate = stats->mbpsSendRate;
  srt_stats.mbpsRecvRate = stats->mbpsRecvRate;
  srt_stats.usSndDuration = stats->usSndDuration;
  srt_stats.pktReorderDistance = stats->pktReorderDistance;
  srt_stats.pktRcvBelated = stats->pktRcvBelated;
  srt_stats.pktSndDrop = stats->pktSndDrop;
  srt_stats.pktRcvDrop = stats->pktRcvDrop;

  return srt_stats;
}

UNIFEX_TERM start_server(UnifexEnv* env,
                         char* address,
                         int port,
                         char* password,
                         int latency_ms) {
  State* state = unifex_alloc_state(env);
  state = new (state) State();

  try {
    state->env = unifex_alloc_env(env);
    if (!unifex_self(env, &state->owner)) {
      throw new std::runtime_error("failed to create native state");
    };

    state->server = std::make_unique<Server>();

    state->server->SetOnSocketConnected(
        [=](Server::SrtSocket socket, const std::string& stream_id) {
          std::lock_guard lock(state->conn_receivers_mutex);

          if (auto it = state->conn_receivers.find(socket); it != std::end(state->conn_receivers)) {
            send_srt_server_conn(
                state->env, it->second, 1, socket, stream_id.c_str());
          }

        });

    state->server->SetOnSocketDisconnected([=](Server::SrtSocket socket) {
      std::lock_guard lock(state->conn_receivers_mutex);

      if (auto it = state->conn_receivers.find(socket); it != std::end(state->conn_receivers)) {
        send_srt_server_conn_closed(state->env, it->second, 1, socket);
      }

      state->conn_receivers.erase(socket);
    });

    state->server->SetOnSocketData(
        [=](Server::SrtSocket socket, const char* data, int len) {
          UnifexPayload* payload =
              (UnifexPayload*)unifex_alloc(sizeof(UnifexPayload));

          unifex_payload_alloc(state->env, UNIFEX_PAYLOAD_BINARY, len, payload);

          memcpy(payload->data, data, len);

          {
            std::unique_lock lock(state->conn_receivers_mutex);
            if (auto it = state->conn_receivers.find(socket); it != std::end(state->conn_receivers)) {
              // TODO: make sure that the message has been properly sent
              send_srt_data(state->env, it->second, 1, socket, payload);
            }
          }

          unifex_payload_release(payload);

          unifex_free(payload);
        });

    state->server->SetOnConnectRequest(
        [=](const std::string& address, const std::string& stream_id) {
          send_srt_server_connect_request(
              state->env, state->owner, 1, address.c_str(), stream_id.c_str());
        });

    state->server->Run(std::string(address), port, std::string(password), latency_ms);

    UNIFEX_TERM result = start_server_result_ok(env, state);
    unifex_release_state(env, state);

    return result;
  } catch (const std::exception& e) {
    unifex_release_state(env, state);

    return start_server_result_error(env, e.what());
  }
}

UNIFEX_TERM accept_awaiting_connect_request(UnifexEnv *env, UnifexPid receiver,
                                            UnifexState *state) {
  if (state->server == nullptr) {
    return accept_awaiting_connect_request_result_error(env, "Server is not active");
  }

  auto id = state->server->GetAwaitingConnectionRequestId();
  state->server->AnswerConnectRequest(true);

  std::lock_guard lock(state->conn_receivers_mutex);
  state->conn_receivers.insert({id, receiver});

  return accept_awaiting_connect_request_result_ok(env);
}

UNIFEX_TERM read_server_socket_stats(UnifexEnv* env, int conn_id, UnifexState* state) {
  if (state->server == nullptr) {
    return read_server_socket_stats_result_error(env, "Server is not active");
  }

  auto stats = state->server->ReadSocketStats(conn_id, true);
  if (!stats) {
    return read_server_socket_stats_result_error(env, "Socket not found");
  }

  auto srt_stats = map_socket_stats(stats.get());

  return read_server_socket_stats_result_ok(env, srt_stats);
}

UNIFEX_TERM reject_awaiting_connect_request(UnifexEnv* env,
                                            UnifexState* state) {
  if (state->server == nullptr) {
    return accept_awaiting_connect_request_result_error(env, "Server is not active");
  }

  state->server->AnswerConnectRequest(false);

  return accept_awaiting_connect_request_result_ok(env);
}


UNIFEX_TERM stop_server(UnifexEnv* env, UnifexState* state) {
  if (state->server == nullptr) {
    return stop_server_result_error(env, "Server is not active");
  }

  close_all_connections(state);
  state->server->Stop();
  state->server = nullptr;

  return stop_server_result_ok(env);
}

UNIFEX_TERM
close_server_connection(UnifexEnv* env, int conn_id, UnifexState* state) {
  if (state->server == nullptr) {
    return accept_awaiting_connect_request_result_error(env, "Server is not active");
  }

  if (state->server) {
    state->server->CloseConnection(conn_id);
  }

  return close_server_connection_result_ok(env);
}

UNIFEX_TERM
start_client(UnifexEnv* env,
             char* server_address,
             int port,
             char* stream_id,
             char* password,
             int latency_ms) {
  State* state = unifex_alloc_state(env);
  state = new (state) State();

  try {
    state->env = unifex_alloc_env(env);
    if (!unifex_self(env, &state->owner)) {
      throw new std::runtime_error("failed to create native state");
    };

    state->client = std::make_unique<Client>(10, 200);

    state->client->SetOnSocketConnected(
        [=]() { send_srt_client_connected(state->env, state->owner, 1); });

    state->client->SetOnSocketDisconnected(
        [=]() { send_srt_client_disconnected(state->env, state->owner, 1); });

    state->client->SetOnSocketError([=](const std::string& reason) {
      send_srt_client_error(state->env, state->owner, 1, reason.c_str());
    });

    state->client->Run(std::string(server_address),
                       port,
                       std::string(stream_id),
                       std::string(password),
                       latency_ms);

    UNIFEX_TERM result = start_client_result_ok(env, state);
    unifex_release_state(env, state);

    return result;
  } catch (const Client::StreamRejectedException& e) {
    auto code = e.GetCode();

    unifex_release_state(env, state);

    return start_client_result_error(env, e.what(), code);
  } catch (const std::exception& e) {
    unifex_release_state(env, state);

    return start_client_result_error(env, e.what(), -1);
  }
}


UNIFEX_TERM
send_client_data(UnifexEnv* env, UnifexPayload* payload, UnifexState* state) {
  if (state->client == nullptr) {
    return send_client_data_result_error(env, "Client is not active");
  } 

  try {
    auto buffer = std::unique_ptr<char[]>(new char[payload->size]);

    memcpy(buffer.get(), payload->data, payload->size);

    state->client->Send(std::move(buffer), payload->size);

    return send_client_data_result_ok(env);
  } catch (const std::exception& e) {
    return send_client_data_result_error(env, e.what());
  }
}

UNIFEX_TERM read_client_socket_stats(UnifexEnv* env, UnifexState* state) {
  if (state->client == nullptr) {
    return read_client_socket_stats_result_error(env, "Client is not active");
  }

  auto stats = state->client->ReadSocketStats(true);
  if (!stats) {
    return read_client_socket_stats_result_error(env, "Failed to read client socket stats");
  }

  auto srt_stats = map_socket_stats(stats.get());

  return read_client_socket_stats_result_ok(env, srt_stats);
}

UNIFEX_TERM stop_client(UnifexEnv* env, UnifexState* state) {
  if (state->client == nullptr) {
    return stop_client_result_error(env, "Client is not active");
  }

  state->client->Stop();
  state->client = nullptr;

  return stop_client_result_ok(env);
}
