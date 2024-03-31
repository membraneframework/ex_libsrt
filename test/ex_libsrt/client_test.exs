defmodule ExLibSRT.ClientTest do
  use ExUnit.Case, async: true

  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  setup :prepare_streaming

  test "connect to the server", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, _client} = ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected
  end

  test "send data to a server", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)
    receiver = Transmit.start_stream_receiver(ctx.udp_port)

    assert {:ok, client} = ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    for _i <- 0..10 do
      :ok = ExLibSRT.send_client_data("test payload", client)

      assert {:ok, "test payload"} = Transmit.receive_payload(receiver)
    end
  end

  test "disconnect from the server", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    :ok = ExLibSRT.stop_client(client)

    {:error, "Client is not active"} = ExLibSRT.send_client_data("test payload", client)
  end

  test "get disconnected notification when servers closes", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = ExLibSRT.start_client("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    Transmit.stop_proxy(proxy)

    assert_receive :srt_client_disconnected, 500

    assert {:error, "Client is not active"} = ExLibSRT.send_client_data("some payload", client)
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
