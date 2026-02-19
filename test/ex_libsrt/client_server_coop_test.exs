defmodule ExLibSRT.ClientServerCoopTest do
  use ExUnit.Case, async: true

  alias ExLibSRT.{Client, Server}

  setup :prepare_streaming

  test "connect client to the server", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      assert_receive {:srt_server_connect_request, _address, "some_stream_id"}

      Server.accept_awaiting_connect_request(server)

      assert_receive {:srt_server_conn, conn_id, _stream_id}, 1000

      assert_receive {:srt_server_conn_closed, ^conn_id}, 2000

      Process.sleep(100)

      Server.stop(server)

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :srt_client_connected, 500

    Process.sleep(200)

    :ok = Client.stop(client)

    assert_receive :stopped, 8000
  end

  test "receive data in caller mode when client is started as receiver", ctx do
    parent = self()

    {:ok, server_task} =
      Task.start(fn ->
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)

        send(parent, :server_running)

        assert_receive {:srt_server_connect_request, _address, "some_stream_id"}, 1_000
        :ok = Server.accept_awaiting_connect_request(server)

        assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000
        send(parent, {:server_connected, server, conn_id})

        receive do
          :stop_server -> :ok
        after
          15_000 -> :ok
        end

        Server.stop(server)
        send(parent, :server_stopped)
      end)

    assert_receive :server_running, 1_000

    assert {:ok, client} =
             Client.start("127.0.0.1", ctx.srt_port, "some_stream_id", mode: :receiver)

    on_exit(fn ->
      _ =
        try do
          Client.stop(client)
        catch
          :exit, _reason -> :ok
        end

      :ok
    end)

    assert_receive :srt_client_connected, 2_000
    assert_receive {:server_connected, server, conn_id}, 2_000

    assert :ok = Server.send_data(conn_id, "hello", server)
    assert_receive {:srt_data, 0, "hello"}, 5_000

    assert {:error, "Client is not in sender mode"} = Client.send_data("hello", client)

    send(server_task, :stop_server)
    assert_receive :server_stopped, 2_000
  end

  test "reject client connection", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      assert_receive {:srt_server_connect_request, _address, "some_stream_id"}

      Server.reject_awaiting_connect_request(server)

      Process.sleep(100)

      Server.stop(server)

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:error, "Stream rejected by server", 403} =
             Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :stopped, 2_000
  end

  test "reject client when timeing out the request awaiting time", ctx do
    parent = self()

    Task.start(fn ->
      assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)

      send(parent, :running)

      Process.sleep(1_000)

      Process.sleep(100)

      Server.stop(server)

      send(parent, :stopped)
    end)

    assert_receive :running, 500

    assert {:error, "Stream rejected by server", 504} =
             Client.start("127.0.0.1", ctx.srt_port, "some_stream_id")

    assert_receive :stopped, 2_000
  end

  # Password authentication tests
  describe "client-server password authentication" do
    test "successful connection with matching passwords", ctx do
      password = "validpassword123"
      parent = self()

      Task.start(fn ->
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port, password)
        send(parent, :server_running)

        assert_receive {:srt_server_connect_request, _address, "auth_stream"}
        Server.accept_awaiting_connect_request(server)

        assert_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000

        send(parent, :connection_accepted)

        Server.stop(server)
      end)

      assert_receive :server_running, 1_000

      assert {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "auth_stream", password)
      assert_receive :srt_client_connected, 2_000
      assert_receive :connection_accepted, 1_000

      Client.stop(client)
    end

    test "failed connection with mismatched passwords", ctx do
      server_password = "serverpassword123"
      client_password = "clientpassword123"
      parent = self()

      Task.start(fn ->
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port, server_password)
        send(parent, :server_running)

        # Server may receive connect request but should reject due to password mismatch
        receive do
          {:srt_server_connect_request, _address, "auth_stream"} ->
            Server.accept_awaiting_connect_request(server)
        after
          2_000 -> :timeout
        end

        Server.stop(server)

        send(parent, :server_done)
      end)

      assert_receive :server_running, 1_000

      # Client should fail to connect due to password mismatch
      assert {:error, _reason, _code} =
               Client.start("127.0.0.1", ctx.srt_port, "auth_stream", client_password)

      assert_receive :server_done, 2_000
    end

    test "failed connection when server has password but client doesn't", ctx do
      server_password = "serverpassword123"
      parent = self()

      Task.start(fn ->
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port, server_password)
        send(parent, :server_running)

        receive do
          {:srt_server_connect_request, _address, "auth_stream"} ->
            Server.accept_awaiting_connect_request(server)
        after
          2_000 -> :timeout
        end

        Server.stop(server)

        send(parent, :server_done)
      end)

      assert_receive :server_running, 1_000

      # Client without password should fail to connect
      assert {:error, _reason, _code} =
               Client.start("127.0.0.1", ctx.srt_port, "auth_stream")

      assert_receive :server_done, 2_000
    end

    test "failed connection when client has password but server doesn't", ctx do
      client_password = "clientpassword123"
      parent = self()

      Task.start(fn ->
        # No password
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)
        send(parent, :server_running)

        receive do
          {:srt_server_connect_request, _address, "auth_stream"} ->
            Server.accept_awaiting_connect_request(server)
        after
          2_000 -> :timeout
        end

        Server.stop(server)

        send(parent, :server_done)
      end)

      assert_receive :server_running, 1_000

      # Client with password should fail to connect to server without password
      assert {:error, _reason, _code} =
               Client.start("127.0.0.1", ctx.srt_port, "auth_stream", client_password)

      assert_receive :server_done, 2_000
    end

    test "successful connection when both have no password", ctx do
      parent = self()

      Task.start(fn ->
        # No password
        assert {:ok, server} = Server.start("127.0.0.1", ctx.srt_port)
        send(parent, :server_running)

        assert_receive {:srt_server_connect_request, _address, "no_auth_stream"}
        Server.accept_awaiting_connect_request(server)

        assert_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000

        send(parent, :connection_accepted)

        Server.stop(server)
      end)

      assert_receive :server_running, 1_000

      # No password
      {:ok, client} = Client.start("127.0.0.1", ctx.srt_port, "no_auth_stream")
      assert_receive :srt_client_connected, 2_000
      assert_receive :connection_accepted, 1_000

      Client.stop(client)
    end
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
