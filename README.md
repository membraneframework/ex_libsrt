# ExLibSRT

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

