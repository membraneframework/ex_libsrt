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

    for _i <- 0..10 do
      :ok = Client.send_data("test payload", client)

      assert {:ok, "test payload"} = Transmit.receive_payload(receiver)
    end
  end

  test "disconnect from the server", ctx do
    _proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    :ok = Client.stop(client)

    assert {:error, "Client is not active"} = Client.send_data("test payload", client)
  end

  test "get disconnected notification when servers closes", ctx do
    proxy = Transmit.start_receiving_proxy(ctx.srt_port, ctx.udp_port)

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected

    Transmit.stop_proxy(proxy)

    assert_receive :srt_client_disconnected, 500

    assert {:error, "Client is not active"} = Client.send_data("some payload", client)
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

  # Password validation tests
  describe "client password validation" do
    test "rejects too short password" do
      assert {:error, "SRT password must be at least 10 characters long", 0} =
               Client.start_link("127.0.0.1", 8080, "stream1", "short")
    end

    test "rejects too long password" do
      long_password = String.duplicate("a", 80)

      assert {:error, "SRT password must be at most 79 characters long", 0} =
               Client.start_link("127.0.0.1", 8080, "stream1", long_password)
    end

    test "accepts valid password length without server", _ctx do
      # This will fail connection but password validation should pass
      valid_password = "validpassword123"

      assert {:error, "Stream rejected by server", -984} =
               Client.start_link("127.0.0.1", 9999, "stream1", valid_password)
    end

    test "accepts empty password (no auth) without server", _ctx do
      # This will fail connection but password validation should pass
      assert {:error, "Stream rejected by server", -984} =
               Client.start_link("127.0.0.1", 9999, "stream1", "")
    end

    test "accepts no password parameter (default) without server", _ctx do
      # This will fail connection but should use default empty password
      assert {:error, "Stream rejected by server", -984} =
               Client.start_link("127.0.0.1", 9999, "stream1")
    end
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
