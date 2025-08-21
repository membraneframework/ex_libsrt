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
        sources: ["srt_nif.cpp", "server/server.cpp", "client/client.cpp", "common/srt_socket_stats.cpp"],
        deps: [unifex: :unifex],
        os_deps: [srt: [{:precompiled, get_srt_url()}, :pkg_config], openssl: :pkg_config],
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
  
  defp get_srt_url() do
    membrane_precompiled_url_prefix = "https://github.com/membraneframework-precompiled/precompiled_srt/releases/download/v1.5.4/srt"

    case Bundlex.get_target() do
      %{os: "linux"} ->
        "#{membrane_precompiled_url_prefix}_linux.tar.gz"

      %{architecture: "aarch64", os: "darwin" <> _rest_of_os_name} ->
        "#{membrane_precompiled_url_prefix}_macos_arm.tar.gz"

      _other ->
        nil
    end
  end
end
