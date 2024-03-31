defmodule ExLibSRT.ClientServerCoopTest do
  use ExUnit.Case, async: true

  setup :prepare_streaming

  test "connect client to the server", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, server} = ExLibSRT.start_server("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      assert_receive {:srt_server_connect_request, _address, "some_stream_id"}

      ExLibSRT.accept_awaiting_connect_request(server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}

      assert_receive {:srt_server_conn_closed, ^conn_id}

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:ok, client} = ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    :ok = ExLibSRT.stop_client(client)

    assert_receive :stopped
  end

  test "reject client connection", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, server} = ExLibSRT.start_server("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      assert_receive {:srt_server_connect_request, _address, "some_stream_id"}

      ExLibSRT.reject_awaiting_connect_request(server)

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:error, "Stream rejected by server", 403} =
             ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :stopped
  end

  test "reject client when timeing out the request awaiting time", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, _server} = ExLibSRT.start_server("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      Process.sleep(1_000)

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:error, "Stream rejected by server", 504} =
             ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :stopped, 1_000
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
