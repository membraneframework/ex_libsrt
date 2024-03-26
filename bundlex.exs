defmodule ExLibSRTBundlexProject do
  use Bundlex.Project

  def project do
    [
      natives: natives()
    ]
  end

  defp natives() do
    [
      srt_nif: [
        sources: ["srt_nif.cpp", "server/server.cpp", "client/client.cpp"],
        deps: [unifex: :unifex],
        pkg_configs: ["srt", "openssl"],
        libs: ["pthread"],
        interface: :nif,
        preprocessor: Unifex,
        language: :cpp,
        compiler_flags: [
          "-std=c++17",
        ]
      ]
    ]
  end
end
