defmodule ExLibSRT.ServerTest do
  use ExUnit.Case, async: false

  alias ExLibSRT.Server
  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  describe "server" do
    setup :prepare_streaming

    @tag :srt_tools_required
    test "accept a new connection", ctx do
      stream_id = "random_stream_id"

      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          stream_id
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
      assert address == "127.0.0.1"

      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, _conn_id, ^stream_id}, 1_000

      Transmit.stop_proxy(proxy)
    end

    @tag :srt_tools_required
    test "decline the connection", ctx do
      stream_id = "forbidden_stream_id"
      proxy = Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, stream_id)
      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
      assert address == "127.0.0.1"

      Server.reject_awaiting_connect_request(ctx.server)

      refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
    end

    @tag :srt_tools_required
    test "receive data over connection", ctx do
      proxy =
        Transmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

      on_exit(fn -> stop_proxy_safe(proxy) end)

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

      assert_receive {:srt_server_connect_request, address, _stream_id}, 2_000
      assert address == "127.0.0.1"

      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      expected = Enum.map_join(1..10, fn i -> "Hello world! (#{i})" end)

      for i <- 1..10 do
        :ok = Transmit.send_payload(stream, "Hello world! (#{i})")
      end

      :ok = Transmit.close_stream(stream)

      received = collect_srt_data(conn_id, byte_size(expected), 2_000)
      assert received == expected

      Transmit.stop_proxy(proxy)
    end

    @tag :srt_tools_required
    test "send data over connection", ctx do
      stream_id = "server_data_stream_id"
      payload = "Hello from server!"

      receiver = Transmit.start_stream_receiver(ctx.udp_port)
      on_exit(fn -> close_stream_safe(receiver) end)

      proxy = Transmit.start_caller_receiving_proxy(ctx.srt_port, ctx.udp_port, stream_id)
      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
      assert address == "127.0.0.1"

      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, ^stream_id}, 1_000

      assert :ok = Server.send_data(conn_id, payload, ctx.server)
      assert {:ok, ^payload} = Transmit.receive_payload(receiver)
    end

    @tag :srt_tools_required
    test "can handle multiple connections", ctx do
      streams =
        for udp_port <- ctx.udp_port..(ctx.udp_port + 10), into: %{} do
          proxy = Transmit.start_streaming_proxy(udp_port, ctx.srt_port, "stream_#{udp_port}")
          on_exit(fn -> stop_proxy_safe(proxy) end)

          assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000

          :ok = Server.accept_awaiting_connect_request(ctx.server)

          assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

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
      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port,
          "closing_stream_id"
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      :ok = Transmit.stop_proxy(proxy)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 2_000
    end

    @tag :srt_tools_required
    test "close an ongoing connection", ctx do
      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      Server.close_server_connection(conn_id, ctx.server)

      assert_receive {:srt_server_conn_closed, ^conn_id}, 1_000
    end

    @tag :srt_tools_required
    test "read socket stats", ctx do
      proxy =
        Transmit.start_streaming_proxy(
          ctx.udp_port,
          ctx.srt_port
        )

      on_exit(fn -> stop_proxy_safe(proxy) end)

      assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
      :ok = Server.accept_awaiting_connect_request(ctx.server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

      payload = :crypto.strong_rand_bytes(100)
      expected = String.duplicate(payload, 10)

      for _i <- 1..10 do
        :ok = Transmit.send_payload(stream, payload)
      end

      received = collect_srt_data(conn_id, byte_size(expected), 2_000)
      assert received == expected

      assert {:ok, stats} = Server.read_socket_stats(conn_id, ctx.server)

      assert %ExLibSRT.SocketStats{} = stats
      assert stats.pktRecv == 10
      assert stats.byteRecvTotal > 1_000

      assert {:error, "Socket not found"} = Server.read_socket_stats(2137, ctx.server)
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

      on_exit(fn -> stop_proxy_safe(proxy) end)

      stream = Transmit.start_stream(ctx.udp_port)
      on_exit(fn -> close_stream_safe(stream) end)

      assert_receive {:srt_server_connect_request, address, _stream_id}, 2_000
      assert address == "127.0.0.1"

      assert {:ok, connection} =
               Server.accept_awaiting_connect_request_with_handler(ReceiverHandler, ctx.server)

      assert is_pid(connection)

      refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
      assert_receive {:srt_handler_connected, _conn_id, _stream_id}, 1_000

      expected = Enum.map_join(1..10, fn i -> "Hello world! (#{i})" end)

      for i <- 1..10 do
        :ok = Transmit.send_payload(stream, "Hello world! (#{i})")
      end

      :ok = Transmit.close_stream(stream)

      received = collect_handler_data(byte_size(expected), 2_000)
      assert received == expected

      Transmit.stop_proxy(proxy)

      refute_receive {:srt_server_conn_closed, _conn_id}, 1_000
      assert_receive :srt_handler_disconnected, 1_000
    end
  end

  describe "server send_data/3" do
    test "rejects payloads larger than 1316 bytes" do
      payload = :crypto.strong_rand_bytes(1_317)

      assert {:error, :payload_too_large} = Server.send_data(123, payload, :unused)
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

  # Collect coalesced {:srt_data, conn_id, payload} messages until we have
  # at least `expected_bytes` bytes or `timeout_ms` elapses.
  defp collect_srt_data(conn_id, expected_bytes, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect_srt_data(conn_id, [], 0, expected_bytes, deadline)
  end

  defp do_collect_srt_data(_conn_id, acc, collected, expected, _deadline) when collected >= expected do
    IO.iodata_to_binary(Enum.reverse(acc))
  end

  defp do_collect_srt_data(conn_id, acc, collected, expected, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:srt_data, ^conn_id, payload} ->
        do_collect_srt_data(conn_id, [payload | acc], collected + byte_size(payload), expected, deadline)
    after
      remaining ->
        flunk("Timed out waiting for srt_data: got #{collected}/#{expected} bytes")
    end
  end

  # Same for {:srt_handler_data, payload} messages from Connection.Handler.
  defp collect_handler_data(expected_bytes, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect_handler_data([], 0, expected_bytes, deadline)
  end

  defp do_collect_handler_data(acc, collected, expected, _deadline) when collected >= expected do
    IO.iodata_to_binary(Enum.reverse(acc))
  end

  defp do_collect_handler_data(acc, collected, expected, deadline) do
    remaining = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:srt_handler_data, payload} ->
        do_collect_handler_data([payload | acc], collected + byte_size(payload), expected, deadline)
    after
      remaining ->
        flunk("Timed out waiting for srt_handler_data: got #{collected}/#{expected} bytes")
    end
  end
end
