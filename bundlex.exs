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
        os_deps: [srt: :pkg_config, openssl: :pkg_config],
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
