#include "srt_nif.h"
#include <thread>

#include <srt/srt.h>

int on_load(UnifexEnv* env, void** priv_data) {
  UNIFEX_UNUSED(env);
  UNIFEX_UNUSED(priv_data);

  srt_startup();

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

    state->server->Initialize(address, port);

    state->server->SetOnSocketConnected([=](Server::SrtSocket socket) {
      send_srt_client_connected(state->env, state->owner, 1, socket);
    });

    state->server->SetOnSocketDisconnected([=](Server::SrtSocket socket) {
      send_srt_client_disconnected(state->env, state->owner, 1, socket);
    });

    state->server->SetOnSocketData([=](Server::SrtSocket socket, const char* data, int len) {
      UnifexPayload* payload = (UnifexPayload*)unifex_alloc(sizeof(UnifexPayload*));

      unifex_payload_alloc(
        state->env, UNIFEX_PAYLOAD_BINARY, len, payload);

      memcpy(payload->data, data, len);

      send_srt_data(state->env, state->owner, 1, socket, payload);

      unifex_payload_release(payload);

      unifex_free(payload);
    });

    state->server->Run();

    UNIFEX_TERM result = start_server_result_ok(env, state);
    unifex_release_state(env, state);

    return result;
  } catch (const std::exception& e) {
    unifex_release_state(env, state);

    return start_server_result_error(env, e.what());
  }
}

UNIFEX_TERM stop_server(UnifexEnv* env, UnifexState* state) {
  if (state->server) {
    state->server->Stop();
  }

  return stop_server_result_ok(env);
}

UNIFEX_TERM close_server_connection(UnifexEnv* env, int conn_id, UnifexState* state) {
  if (state->server) {
    state->server->CloseConnection(conn_id);
  }

  return close_server_connection_result_ok(env);
}

UNIFEX_TERM start_client(UnifexEnv* env, char* server_address, int port) {

  return start_client_result_ok(env);
}