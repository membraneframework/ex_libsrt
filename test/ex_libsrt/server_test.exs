defmodule ExLibSRT.ServerTest do
  use ExUnit.Case, async: false

  alias ExLibSRT.Server
  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  describe "server" do
    setup :prepare_streaming

    test "accept a new connection", ctx do
      stream_id = "random_stream_id"

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          stream_id
        )

      assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
      assert address == "127.0.0.1"

      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, _conn_id, ^stream_id}, 1_000

      Transmit.stop_proxy(proxy)
    end

    test "decline the connection", ctx do
      stream_id = "forbidden_stream_id"
      _proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, stream_id)

      assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
      assert address == "127.0.0.1"

      Server.reject_awaiting_connect_request(ctx.server)

      refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
    end

    test "receive data over connection", ctx do
      proxy =
        Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

      stream = Transmit.start_stream(ctx.udp_port)

      assert_receive {:srt_server_connect_request, address, _stream_id}, 2_000
      assert address == "127.0.0.1"

      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      for i <- 1..10 do
        :ok = Transmit.send_payload(stream, "Hello world! (#{i})")
      end

      :ok = Transmit.close_stream(stream)

      for i <- 1..10 do
        assert_receive {:srt_data, ^conn_id, payload}, 500
        assert payload == "Hello world! (#{i})"
      end

      Transmit.stop_proxy(proxy)
    end

    test "can handle multiple connections", ctx do
      streams =
        for udp_port <- ctx.udp_port..(ctx.udp_port + 10), into: %{} do
          proxy = Transmit.start_streaming_proxy(udp_port, ctx.srt_port, "stream_#{udp_port}")

          assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000

          :ok = Server.accept_awaiting_connect_request(ctx.server)

          assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

          stream = Transmit.start_stream(udp_port)

          {conn_id, %{stream: stream, proxy: proxy}}
        end

      for {conn_id, %{stream: stream}} <- streams do
        :ok = Transmit.send_payload(stream, "#{conn_id}")
        :ok = Transmit.close_stream(stream)
      end

      for {conn_id, _data} <- streams do
        payload = "#{conn_id}"
        assert_receive {:srt_data, ^conn_id, ^payload}, 500
      end
    end

    test "send closed connection notification", ctx do
      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          "closing_stream_id"
        )

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      :ok = Transmit.stop_proxy(proxy)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 2_000
    end

    test "close an ongoing connection", ctx do
      _proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port
        )

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      Server.close_server_connection(conn_id, ctx.server)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 1_000
    end

    test "read socket stats", ctx do
      _proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port
        )

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      stream = Transmit.start_stream(ctx.udp_port)

      payload = :crypto.strong_rand_bytes(100)

      for _i <- 1..10 do
        :ok = Transmit.send_payload(stream, payload)

        assert_receive {:srt_data, ^conn_id, ^payload}, 1_000
      end

      assert {:ok, stats} = Server.read_socket_stats(conn_id, ctx.server)

      assert %ExLibSRT.SocketStats{} = stats
      assert stats.pktRecv == 10
      assert stats.byteRecvTotal > 1_000

      assert {:error, "Socket not found"} = Server.read_socket_stats(2137, ctx.server)
    end

    test "starts a separate connection process", ctx do
      :persistent_term.put(:srt_receiver, self())

      defmodule ReceiverHandler do
        @behaviour ExLibSRT.Connection.Handler

        @impl true
        def init(_args) do
          :persistent_term.get(:srt_receiver)
        end

        def handle_connected(conn_id, stream_id, receiver) do
          send(receiver, {:srt_handler_connected, conn_id, stream_id})

          {:ok, receiver}
        end

        @impl true
        def handle_disconnected(receiver) do
          send(receiver, :srt_handler_disconnected)

          :ok
        end

        @impl true
        def handle_data(data, receiver) do
          send(receiver, {:srt_handler_data, data})

          {:ok, receiver}
        end
      end

      proxy =
        Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

      stream = Transmit.start_stream(ctx.udp_port)

      assert_receive {:srt_server_connect_request, address, _stream_id}, 2_000
      assert address == "127.0.0.1"

      assert {:ok, connection} =
               Server.accept_awaiting_connect_request_with_handler(ReceiverHandler, ctx.server)

      assert is_pid(connection)

      refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
      assert_receive {:srt_handler_connected, _conn_id, _stream_id}, 1_000

      for i <- 1..10 do
        :ok = Transmit.send_payload(stream, "Hello world! (#{i})")
      end

      :ok = Transmit.close_stream(stream)

      for i <- 1..10 do
        assert_receive {:srt_handler_data, payload}, 500
        assert payload == "Hello world! (#{i})"
      end

      Transmit.stop_proxy(proxy)

      refute_receive {:srt_server_conn_closed, _conn_id}, 1_000
      assert_receive :srt_handler_disconnected, 1_000
    end
  end

  # Password validation tests
  describe "server password validation" do
    test "rejects too short password" do
      assert {:error, "SRT password must be at least 10 characters long", 0} =
               Server.start_link("127.0.0.1", 8080, "short")
    end

    test "rejects too long password" do
      long_password = String.duplicate("a", 80)

      assert {:error, "SRT password must be at most 79 characters long", 0} =
               Server.start_link("127.0.0.1", 8080, long_password)
    end

    test "accepts valid password length" do
      valid_password = "validpassword123"
      {:ok, server} = Server.start_link("127.0.0.1", 8080, valid_password)
      assert is_pid(server)
      Server.stop(server)
    end

    test "accepts empty password (no auth)" do
      {:ok, server} = Server.start_link("127.0.0.1", 8080, "")
      assert is_pid(server)
      Server.stop(server)
    end

    test "accepts no password parameter (default)" do
      {:ok, server} = Server.start_link("127.0.0.1", 8080)
      assert is_pid(server)
      Server.stop(server)
    end
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    {:ok, server} = Server.start("0.0.0.0", srt_port)
    on_exit(fn -> Server.stop(server) end)

    [udp_port: udp_port, srt_port: srt_port, server: server]
  end
end
