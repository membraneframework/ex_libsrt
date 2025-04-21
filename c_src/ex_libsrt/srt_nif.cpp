#include <fine.hpp>

#include "client/client.h"
#include "common/socket_stats.h"
#include "server/server.h"
#include <memory>
#include <shared_mutex>
#include <string>
#include <variant>

int64_t on_load(ErlNifEnv*) {
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

FINE_NIF(on_load, ERL_NIF_DIRTY_JOB_IO_BOUND);

struct ServerContext {
  ErlNifPid owner;
  ErlNifEnv* env;
  std::unordered_map<int, ErlNifPid> conn_receivers;
  std::shared_mutex conn_receivers_mutex;

  ServerContext() { this->env = enif_alloc_env(); }

  void BindOwner(ErlNifEnv* env) {
    if (enif_self(env, &this->owner) == nullptr) {
      throw std::runtime_error("failed to bind owner pid");
    }
  }

  ~ServerContext() { enif_free_env(this->env); }
};

struct ServerResource {
  std::unique_ptr<Server> server;
  std::shared_ptr<ServerContext> ctx;

  ServerResource(std::unique_ptr<Server> server,
                 std::shared_ptr<ServerContext> ctx)
      : server{std::move(server)}, ctx{std::move(ctx)} {};

  void destructor(ErlNifEnv*) {
    if (server != nullptr) {
      server->Stop();
    }
  }
};

FINE_RESOURCE(ServerResource);

std::variant<fine::Ok<fine::ResourcePtr<ServerResource>>,
             fine::Error<std::string>>
create_server(ErlNifEnv* env, std::string address, int64_t port) {
  auto server = std::make_unique<Server>();
  auto ctx = std::make_shared<ServerContext>();

  ctx->BindOwner(env);

  server->SetOnSocketConnected([=](Server::SrtSocket socket,
                                   const std::string& stream_id) {
    std::lock_guard lock(ctx->conn_receivers_mutex);
    if (auto it = ctx->conn_receivers.find(socket);
        it != std::end(ctx->conn_receivers)) {
      auto pid = it->second;
      auto term = fine::encode(ctx->env,
                               std::make_tuple(fine::Atom("srt_server_conn"),
                                               (int64_t)socket,
                                               std::string{stream_id}));
      enif_send(nullptr, &pid, ctx->env, term);
    }
  });

  server->SetOnSocketDisconnected([=](Server::SrtSocket socket) {
    std::lock_guard lock(ctx->conn_receivers_mutex);

    if (auto it = ctx->conn_receivers.find(socket);
        it != std::end(ctx->conn_receivers)) {
      auto pid = it->second;
      auto term =
          fine::encode(ctx->env,
                       std::make_tuple(fine::Atom("srt_server_conn_closed"),
                                       (int64_t)socket));
      enif_send(nullptr, &pid, ctx->env, term);
    }

    ctx->conn_receivers.erase(socket);
  });

  server->SetOnSocketData(
      [=](Server::SrtSocket socket, const char* data, int len) {
        ErlNifBinary binary;
        enif_alloc_binary(len, &binary);
        memcpy(binary.data, data, len);

        enif_make_binary(ctx->env, &binary);

        {
          std::unique_lock lock(ctx->conn_receivers_mutex);
          if (auto it = ctx->conn_receivers.find(socket);
              it != std::end(ctx->conn_receivers)) {
            auto pid = it->second;
            auto term = fine::encode(ctx->env,
                                     std::make_tuple(fine::Atom("srt_data"),
                                                     (int64_t)socket,
                                                     binary));
            enif_send(nullptr, &pid, ctx->env, term);
            enif_clear_env(ctx->env);
            enif_release_binary(&binary);
          }
        }

        enif_release_binary(&binary);
      });

  server->SetOnConnectRequest(
      [=](const std::string& address, const std::string& stream_id) {
        auto term = fine::encode(
            ctx->env,
            std::make_tuple(
                fine::Atom("srt_server_connect_request"), address, stream_id));
        enif_send(nullptr, &ctx->owner, ctx->env, term);
      });

  server->Run(address.c_str(), port);

  return fine::Ok(
      fine::make_resource<ServerResource>(std::move(server), std::move(ctx)));
}

FINE_NIF(create_server, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<>, fine::Error<std::string>>
accept_awaiting_connect_request(ErlNifEnv*,
                                ErlNifPid receiver,
                                fine::ResourcePtr<ServerResource> resource) {
  if (resource->server == nullptr) {
    return fine::Error<std::string>("server is not active");
  }

  auto id = resource->server->GetAwaitingConnectionRequestId();
  resource->server->AnswerConnectRequest(true);

  std::lock_guard lock(resource->ctx->conn_receivers_mutex);
  resource->ctx->conn_receivers.insert({id, receiver});
  return fine::Ok();
}

FINE_NIF(accept_awaiting_connect_request, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<SocketStats>, fine::Error<std::string>>
read_server_socket_stats(ErlNifEnv*,
                         int64_t conn_id,
                         fine::ResourcePtr<ServerResource> resource) {
  if (resource->server == nullptr) {
    return fine::Error<std::string>("server is not active");
  }

  auto stats = resource->server->ReadSocketStats(conn_id, true);
  if (!stats) {
    return fine::Error<std::string>("socket not found");
  }

  SocketStats socket_stats = *stats;

  return fine::Ok(socket_stats);
}

FINE_NIF(read_server_socket_stats, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<>, fine::Error<std::string>>
reject_awaiting_connect_request(ErlNifEnv*,
                                fine::ResourcePtr<ServerResource> resource) {
  if (resource->server == nullptr) {
    return fine::Error<std::string>("server is not active");
  }

  resource->server->AnswerConnectRequest(false);

  return fine::Ok();
}

FINE_NIF(reject_awaiting_connect_request, ERL_NIF_DIRTY_JOB_IO_BOUND);

fine::Ok<> stop_server(ErlNifEnv*, fine::ResourcePtr<ServerResource> resource) {
  if (resource->server) {
    resource->server->Stop();
    resource->server = nullptr;
  }
  resource->ctx = nullptr;

  return fine::Ok();
}

FINE_NIF(stop_server, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<>, fine::Error<std::string>> close_server_connection(
    ErlNifEnv*, int64_t conn_id, fine::ResourcePtr<ServerResource> resource) {
  if (resource->server == nullptr) {
    return fine::Error<std::string>("server is not active");
  }

  if (resource->server) {
    resource->server->CloseConnection(conn_id);
  }

  return fine::Ok();
}

FINE_NIF(close_server_connection, ERL_NIF_DIRTY_JOB_IO_BOUND);

struct ClientContext {
  ErlNifPid owner;
  ErlNifEnv* env;

  ClientContext() { this->env = enif_alloc_env(); }

  void BindOwner(ErlNifEnv* env) {
    if (enif_self(env, &this->owner) == nullptr) {
      throw std::runtime_error("failed to bind owner pid");
    }
  }

  ErlNifPid* Owner() { return &this->owner; }

  ~ClientContext() { enif_free_env(this->env); }
};

struct ClientResource {
  std::unique_ptr<Client> client;
  std::shared_ptr<ClientContext> ctx;

  ClientResource(std::unique_ptr<Client> client,
                 std::shared_ptr<ClientContext> ctx)
      : client{std::move(client)}, ctx{std::move(ctx)} {}

  void destructor(ErlNifEnv*) {
    if (client != nullptr) {
      client->Stop();
    }
  }
};

FINE_RESOURCE(ClientResource);

std::variant<fine::Ok<fine::ResourcePtr<ClientResource>>,
             fine::Error<std::string, int64_t>>
create_client(ErlNifEnv* env,
              std::string server_address,
              int64_t port,
              std::string stream_id) {
  try {
    auto client = std::make_unique<Client>(1000, 200);
    auto ctx = std::make_shared<ClientContext>();
    ctx->BindOwner(env);

    client->SetOnSocketConnected([=]() {
      auto term = fine::encode(ctx->env, fine::Atom("srt_client_connected"));
      enif_send(nullptr, &ctx->owner, ctx->env, term);
    });

    client->SetOnSocketDisconnected([=]() {
      auto term = fine::encode(ctx->env, fine::Atom("srt_client_disconnected"));
      enif_send(nullptr, &ctx->owner, ctx->env, term);
    });

    client->SetOnSocketError([=](const std::string& reason) {
      auto term = fine::encode(
          ctx->env, std::make_tuple(fine::Atom("srt_client_error"), reason));
      enif_send(nullptr, &ctx->owner, ctx->env, term);
    });

    client->Run(server_address.c_str(), port, stream_id.c_str());

    return fine::Ok<fine::ResourcePtr<ClientResource>>(
        fine::make_resource<ClientResource>(std::move(client), std::move(ctx)));
  } catch (const Client::StreamRejectedException& e) {
    auto code = e.GetCode();

    return fine::Error<std::string, int64_t>(e.what(), code);
  } catch (const std::exception& e) {
    return fine::Error<std::string, int64_t>(e.what(), -1);
  }
}

FINE_NIF(create_client, ERL_NIF_DIRTY_JOB_CPU_BOUND);

std::variant<fine::Ok<>, fine::Error<std::string>>
send_client_data(ErlNifEnv*,
                 ErlNifBinary payload,
                 fine::ResourcePtr<ClientResource> resource) {
  if (resource->client == nullptr) {
    return fine::Error<std::string>("client is not active");
  }

  try {
    auto buffer = std::unique_ptr<char[]>(new char[payload.size]);
    memcpy(buffer.get(), payload.data, payload.size);

    resource->client->Send(std::move(buffer), payload.size);

    return fine::Ok<>();
  } catch (const std::exception& e) {
    return fine::Error<std::string>(e.what());
  }
}

FINE_NIF(send_client_data, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<SocketStats>, fine::Error<std::string>>
read_client_socket_stats(ErlNifEnv*,
                         fine::ResourcePtr<ClientResource> resource) {
  if (resource->client == nullptr) {
    return fine::Error<std::string>("client is not active");
  }

  auto stats = resource->client->ReadSocketStats(true);
  if (!stats) {
    return fine::Error<std::string>("failed to read client socket stats");
  }
  SocketStats socket_stats = *stats;
  return fine::Ok<SocketStats>(socket_stats);
}

FINE_NIF(read_client_socket_stats, ERL_NIF_DIRTY_JOB_IO_BOUND);

std::variant<fine::Ok<>, fine::Error<std::string>>
stop_client(ErlNifEnv*, fine::ResourcePtr<ClientResource> resource) {
  if (resource->client == nullptr) {
    return fine::Error<std::string>("client is not active");
  }

  resource->client->Stop();
  resource->client = nullptr;

  return fine::Ok<>();
}
FINE_NIF(stop_client, ERL_NIF_DIRTY_JOB_IO_BOUND);

FINE_INIT("Elixir.ExLibSRT.Native");
