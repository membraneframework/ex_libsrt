# ExLibSRT

[![Hex.pm](https://img.shields.io/hexpm/v/ex_m3u8.svg)](https://hex.pm/packages/ex_m3u8)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/ex_m3u8/)
[![CircleCI](https://circleci.com/gh/membraneframework/ex_m3u8.svg?style=svg)](https://circleci.com/gh/membraneframework/ex_m3u8)

Bindings for [libsrt](https://github.com/Haivision/srt) library

The package exposes a server and a client module to interact with SRT streams.

## Installation

```elixir
def deps do
  [
    {:ex_libsrt, "~> 0.1.0"}
  ]
end

## Client example
```elixir
{:ok, client} = ExLibSRT.Client.start_link()
````

```

