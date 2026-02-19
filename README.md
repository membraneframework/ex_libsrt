# ExLibSRT

[![Hex.pm](https://img.shields.io/hexpm/v/ex_libsrt.svg)](https://hex.pm/packages/ex_libsrt)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_libsrt/)
[![CircleCI](https://circleci.com/gh/membraneframework/ex_libsrt.svg?style=svg)](https://circleci.com/gh/membraneframework/ex_libsrt)

Bindings for the [libsrt](https://github.com/Haivision/srt) library.

The package exposes a server and a client module to interact with SRT streams.

## Installation

```elixir
def deps do
  [
    {:ex_libsrt, "~> 0.1.6"}
  ]
end
```

## Example usage

For examples of how to use the bindings, see `examples/` subdirectory.
To see how to spawn a server listening on given port, how to connect
client to that server and how to send data between the client and the server,
see: `simple_client_connection.exs`.

To see how to handle multiple client connections with a single server using 
`ExLibSRT.Connection.Handler`, see: `connection_handler.exs`.

To send payloads from server to a connected client, use `ExLibSRT.Server.send_data/3`.

## Client modes (`:sender` / `:receiver`)

`ExLibSRT.Client` supports explicit client socket mode via options.
The API is atom-based (`:sender | :receiver`) and does not expose raw integer mode flags:

```elixir
# default mode is :sender
{:ok, client} = ExLibSRT.Client.start("127.0.0.1", 12_000, "stream-id")

# receiver mode (can receive `{:srt_data, conn_id, payload}` messages)
{:ok, client} =
  ExLibSRT.Client.start("127.0.0.1", 12_000, "stream-id", mode: :receiver)

# with password and latency
{:ok, client} =
  ExLibSRT.Client.start("127.0.0.1", 12_000, "stream-id",
    password: "validpassword123",
    latency_ms: 120,
    mode: :receiver
  )
```

You can launch each of these scripts with the following sequence of commands:
```
cd examples/
elixir <script name>
```

## Copyright and License

Copyright 2025, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_template_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
