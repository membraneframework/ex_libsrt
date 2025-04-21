defmodule ExLibSRT.ClientTest do
  use ExUnit.Case, async: true

  alias ExLibSRT.Client
  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  setup :prepare_streaming

  test "connect to the server", ctx do
    _proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, _client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected
  end

  test "send data to a server", ctx do
    _proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)
    receiver = Transmit.start_stream_receiver(ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    payload = :crypto.strong_rand_bytes(1000)

    for _i <- 0..10 do
      :ok = Client.send_data(payload, client)

      assert {:ok, ^payload} = Transmit.receive_payload(receiver)
    end
  end

  test "disconnect from the server", ctx do
    _proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    :ok = Client.stop(client)

    {:error, "client is not active"} = Client.send_data("test payload", client)
  end

  test "get disconnected notification when servers closes", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    Transmit.stop_proxy(proxy)

    assert_receive :srt_client_disconnected, 500

    assert {:error, "client is not active"} = Client.send_data("some payload", client)
  end

  test "read socket stats", ctx do
    _proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)
    receiver = Transmit.start_stream_receiver(ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    payload = :crypto.strong_rand_bytes(100)

    for _i <- 1..10 do
      :ok = Client.send_data(payload, client)

      assert {:ok, ^payload} = Transmit.receive_payload(receiver)
    end

    assert {:ok, stats} = Client.read_socket_stats(client)
    assert stats.pktSent == 10
    assert stats.byteSentTotal > 1_000
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
