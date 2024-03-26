#include "srt_nif.h"
#include <cstdlib>
#include <thread>

#include <srt/srt.h>

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

UNIFEX_TERM start_server(UnifexEnv* env, char* address, int port) {
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
          send_srt_server_conn(
              state->env, state->owner, 1, socket, stream_id.c_str());
        });

    state->server->SetOnSocketDisconnected([=](Server::SrtSocket socket) {
      send_srt_server_conn_closed(state->env, state->owner, 1, socket);
    });

    state->server->SetOnSocketData(
        [=](Server::SrtSocket socket, const char* data, int len) {
          UnifexPayload* payload =
              (UnifexPayload*)unifex_alloc(sizeof(UnifexPayload*));

          unifex_payload_alloc(state->env, UNIFEX_PAYLOAD_BINARY, len, payload);

          memcpy(payload->data, data, len);

          send_srt_data(state->env, state->owner, 1, socket, payload);

          unifex_payload_release(payload);

          unifex_free(payload);
        });

    state->server->SetOnConnectRequest(
        [=](const std::string& address, const std::string& stream_id) {
          send_srt_server_connect_request(
              state->env, state->owner, 1, address.c_str(), stream_id.c_str());
        });

    state->server->Run(address, port);

    UNIFEX_TERM result = start_server_result_ok(env, state);
    unifex_release_state(env, state);

    return result;
  } catch (const std::exception& e) {
    unifex_release_state(env, state);

    return start_server_result_error(env, e.what());
  }
}

UNIFEX_TERM accept_awaiting_connect_request(UnifexEnv* env,
                                            UnifexState* state) {
  state->server->AnswerConnectRequest(true);

  return accept_awaiting_connect_request_result_ok(env);
}

UNIFEX_TERM reject_awaiting_connect_request(UnifexEnv* env,
                                            UnifexState* state) {
  state->server->AnswerConnectRequest(false);

  return accept_awaiting_connect_request_result_ok(env);
}

UNIFEX_TERM stop_server(UnifexEnv* env, UnifexState* state) {
  if (state->server) {
    state->server->Stop();
    state->server = nullptr;
  }

  return stop_server_result_ok(env);
}

UNIFEX_TERM
close_server_connection(UnifexEnv* env, int conn_id, UnifexState* state) {
  if (state->server) {
    state->server->CloseConnection(conn_id);
  }

  return close_server_connection_result_ok(env);
}

UNIFEX_TERM
start_client(UnifexEnv* env, char* server_address, int port, char* stream_id) {
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

    state->client->SetOnSocketError([=](const std::string& reason) {
      send_srt_client_disconnected(state->env, state->owner, 1, reason.c_str());
    });

    state->client->Run(server_address, port, stream_id);

    UNIFEX_TERM result = start_client_result_ok(env, state);
    unifex_release_state(env, state);

    return result;
  } catch (const std::exception& e) {
    unifex_release_state(env, state);

    return start_client_result_error(env, e.what());
  }
}

UNIFEX_TERM
send_client_data(UnifexEnv* env, UnifexPayload* payload, UnifexState* state) {
  try {
    auto buffer = std::unique_ptr<char[]>(new char[payload->size]);

    memcpy(buffer.get(), payload->data, payload->size);

    state->client->Send(std::move(buffer), payload->size);

    return send_client_data_result_ok(env);
  } catch (const std::exception& e) {
    return send_client_data_result_error(env, e.what());
  }
}

UNIFEX_TERM stop_client(UnifexEnv* env, UnifexState* state) {
  if (state->client) {
    state->client->Stop();
    state->client = nullptr;
  }

  return stop_client_result_ok(env);
}