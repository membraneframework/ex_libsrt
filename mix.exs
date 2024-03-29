defmodule ExLibSRT.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_libsrt,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      compilers: Mix.compilers() ++ [:unifex, :bundlex],
      deps: deps()
    ]
  end

  defp elixirc_paths(_env), do: ["lib", "test/support"]
  # defp elixirc_paths(:test), do: ["lib", "test/support"]
  # defp elixirc_paths(_env), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:unifex, "~> 1.2.0"}
    ]
  end
end
