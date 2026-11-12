defmodule ExLibSRT.NativeServerTest do
  use ExUnit.Case, async: false

  alias ExLibSRT.Native

  test "whitelist calls after stop_server return an error" do
    assert {:ok, server} = Native.start_server("127.0.0.1", 47_321, "", -1, false, [], self())
    assert :ok = Native.add_stream_id_to_whitelist("stream", server)
    assert :ok = Native.stop_server(server)

    assert {:error, _reason} = Native.add_stream_id_to_whitelist("stream", server)
    assert {:error, _reason} = Native.remove_stream_id_from_whitelist("stream", server)
  end
end
