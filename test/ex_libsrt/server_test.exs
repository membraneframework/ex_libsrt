defmodule ExLibSRT.ServerTest do
  use ExUnit.Case, async: false

  alias ExLibSRT.Server
  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  describe "server" do
    setup :prepare_streaming

    @tag :srt_tools_required
    test "accept a new connection", ctx do
      stream_id = "random_stream_id"
      :ok = Server.add_stream_id_to_whitelist(ctx.server, stream_id)

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          stream_id
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, ^stream_id}, 1_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

      Transmit.stop_proxy(proxy)
    end

    @tag :srt_tools_required
    test "decline the connection", ctx do
      stream_id = "forbidden_stream_id"
      :ok = Server.add_stream_id_to_whitelist(ctx.server, "other_allowed_stream")

      proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, stream_id)
      on_exit(fn -> stop_proxy_safe(proxy) end)

      refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
    end

    @tag :srt_tools_required
    test "notifies about rejected connection", ctx do
      stream_id = "forbidden_stream_id"
      :ok = Server.add_stream_id_to_whitelist(ctx.server, "other_allowed_stream")

      proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, stream_id)
      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_rejected_client, ^stream_id}, 1_000
    end

    @tag :srt_tools_required
    test "receive data over connection", ctx do
      :ok = Server.add_stream_id_to_whitelist(ctx.server, "data_stream_id")

      proxy =
        Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

      on_exit(fn -> stop_proxy_safe(proxy) end)

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

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

    @tag :srt_tools_required
    test "can handle multiple connections", ctx do
      streams =
        for udp_port <- ctx.udp_port..(ctx.udp_port + 10), into: %{} do
          stream_id = "stream_#{udp_port}"
          :ok = Server.add_stream_id_to_whitelist(ctx.server, stream_id)

          proxy = Transmit.start_streaming_proxy(udp_port, ctx.srt_port, stream_id)
          on_exit(fn -> stop_proxy_safe(proxy) end)

          assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000
          :ok = Server.bind_with_process(ctx.server, conn_id)

          stream = Transmit.start_stream(udp_port)
          on_exit(fn -> close_stream_safe(stream) end)

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

    @tag :srt_tools_required
    test "send closed connection notification", ctx do
      :ok = Server.add_stream_id_to_whitelist(ctx.server, "closing_stream_id")

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          "closing_stream_id"
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 2_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

      :ok = Transmit.stop_proxy(proxy)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 2_000
    end

    @tag :srt_tools_required
    test "close an ongoing connection", ctx do
      stream_id = "stream_id"
      Server.add_stream_id_to_whitelist(ctx.server, stream_id)

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          stream_id
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, ^stream_id}, 2_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

      Server.close_server_connection(conn_id, ctx.server)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 1_000
    end

    @tag :srt_tools_required
    test "starts a separate connection process", ctx do
      :persistent_term.put(:srt_receiver, self())

      defmodule ReceiverHandler do
        @behaviour ExLibSRT.Connection.Handler

        @impl true
        def init(_args) do
          :persistent_term.get(:srt_receiver)
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

      :ok = Server.add_stream_id_to_whitelist(ctx.server, "data_stream_id")

      proxy =
        Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

      on_exit(fn -> stop_proxy_safe(proxy) end)

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 2_000

      {:ok, _connection} = Server.bind_with_handler(ctx.server, conn_id, ReceiverHandler)

      for i <- 1..10 do
        :ok = Transmit.send_payload(stream, "Hello world! (#{i})")
      end

      :ok = Transmit.close_stream(stream)

      for i <- 1..10 do
        assert_receive {:srt_handler_data, payload}, 500
        assert payload == "Hello world! (#{i})"
      end

      Transmit.stop_proxy(proxy)

      assert_receive :srt_handler_disconnected, 1_000
    end

    @tag :srt_tools_required
    test "read socket stats", ctx do
      :ok = Server.add_stream_id_to_whitelist(ctx.server, "stats_stream_id")

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          "stats_stream_id"
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 2_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

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
  end

  describe "server owner" do
    @tag :srt_tools_required
    test "receives rejected client notifications" do
      owner =
        spawn(fn ->
          assert_receive {:srt_server_rejected_client, "unknown_stream_id"}, 1_000
        end)

      srt_port = Enum.random(10_000..20_000)
      udp_port = Enum.random(10_000..20_000)

      {:ok, server} = Server.start("0.0.0.0", srt_port, "", -1, ["some_allowed_stream"], owner)
      on_exit(fn -> Server.stop(server) end)

      proxy = Transmit.start_streaming_proxy(udp_port, srt_port, "unknown_stream_id")
      on_exit(fn -> stop_proxy_safe(proxy) end)

      refute_receive {:srt_server_rejected_client, _stream_id}, 0
    end
  end

  describe "accept-all mode" do
    setup :prepare_streaming_accept_all

    @tag :srt_tools_required
    test "accepts any connection regardless of stream id", ctx do
      proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "any_stream_id")
      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, "any_stream_id"}, 1_000
      :ok = Server.bind_with_process(ctx.server, conn_id)

      Transmit.stop_proxy(proxy)
    end

    @tag :srt_tools_required
    test "notifies owner and drops connection if not bound within 1 second", ctx do
      proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "unbound_stream")
      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_conn, conn_id, "unbound_stream"}, 1_000

      assert_receive {:srt_server_conn_timeout, ^conn_id, "unbound_stream"}, 2_000

      assert {:error, _reason} = Server.bind_with_process(ctx.server, conn_id)
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

  defp prepare_streaming_accept_all(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    {:ok, server} = Server.start("0.0.0.0", srt_port, "", -1, nil)
    on_exit(fn -> Server.stop(server) end)

    [udp_port: udp_port, srt_port: srt_port, server: server]
  end

  defp stop_proxy_safe(proxy) do
    case :erlang.port_info(proxy, :os_pid) do
      {:os_pid, _os_pid} -> Transmit.stop_proxy(proxy)
      _other -> :ok
    end
  end

  defp close_stream_safe(socket) do
    if is_port(socket) and :erlang.port_info(socket) != nil do
      :ok = Transmit.close_stream(socket)
    end
  end
end
