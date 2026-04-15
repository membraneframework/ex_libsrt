defmodule ExLibSRT.MixProject do
  use Mix.Project

  @version "0.1.8"
  @github_url "https://github.com/membraneframework/ex_libsrt"

  def project do
    [
      app: :ex_libsrt,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      compilers: [:unifex, :bundlex] ++ Mix.compilers(),
      deps: deps(),
      # hex
      description: "SRT protocol bindings for low-latency streaming.",
      package: package(),
      # docs
      name: "ExLibSRT",
      source_url: @github_url,
      docs: docs(),
      homepage_url: "https://membrane.stream",
      aliases: [docs: ["docs", &prepend_llms_links/1]]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      },
      files: ["lib", "mix.exs", "README*", "LICENSE*", ".formatter.exs", "bundlex.exs", "c_src"],
      exclude_patterns: [~r"c_src/.*/_generated.*"]
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [ExLibSRT]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:unifex, "~> 1.2.0"},
      {:membrane_precompiled_dependency_provider, "~> 0.2.0"},
      {:credo, "~> 1.4", only: :dev, runtime: false},
      {:dialyxir, "~> 1.1", only: :dev, runtime: false},
      {:ex_doc, "~> 0.40", only: :dev, runtime: false}
    ]
  end

defp prepend_llms_links(_) do
  path = "doc/llms.txt"

  if File.exists?(path) do
    existing = File.read!(path)

    header =
      "- [Membrane Core AI Skill](https://hexdocs.pm/membrane_core/skill.md)\n" <>
        "- [Membrane Core](https://hexdocs.pm/membrane_core/llms.txt)\n\n"

    File.write!(path, header <> existing)
  end
end

end
