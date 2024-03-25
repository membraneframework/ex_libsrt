defmodule ExLibSRT.ServerTest do
  use ExUnit.Case

  setup_all do
    assert :ok = Membrane.SRT.Server.initialize_srt_package()
  end

  test "initialize SRT server" do
    assert {:ok, _srt} = ExLibSRT.Server.init("0.0.0.0", 10000)

    :timer.sleep(20_000)
  end
end
