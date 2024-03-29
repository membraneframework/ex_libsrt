defmodule ExLibSRT.ServerTest do
  use ExUnit.Case, async: true

  alias ExLibSRT.SRTLiveTransmit, as: Transmit

  @moduletag :tmp_dir

  setup :prepare_file

  setup :prepare_streaming

  test "accept a new connection", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    stream_id = "random_stream_id"

    proxy =
      Transmit.start_streaming_proxy(
        ctx.udp_port,
        ctx.srt_port,
        stream_id
      )

    assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
    assert address == "127.0.0.1"

    ExLibSRT.accept_awaiting_connect_request(server)

    assert_receive {:srt_server_conn, _conn_id, ^stream_id}, 1_000

    Transmit.stop_proxy(proxy)
  end

  test "decline the connection", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    stream_id = "forbidden_stream_id"
    _proxy = ExLibSRT.SRTLiveTransmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, stream_id)

    assert_receive {:srt_server_connect_request, address, ^stream_id}, 2_000
    assert address == "127.0.0.1"

    ExLibSRT.reject_awaiting_connect_request(server)

    refute_receive {:srt_server_conn, _conn_id, _stream_id}, 1_000
  end

  test "receive data over connection", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    proxy =
      ExLibSRT.SRTLiveTransmit.start_streaming_proxy(ctx.udp_port, ctx.srt_port, "data_stream_id")

    stream = ExLibSRT.SRTLiveTransmit.start_stream(ctx.udp_port)

    assert_receive {:srt_server_connect_request, address, _stream_id}, 2_000
    assert address == "127.0.0.1"

    ExLibSRT.accept_awaiting_connect_request(server)

    assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

    for i <- 1..10 do
      :ok = ExLibSRT.SRTLiveTransmit.send_payload(stream, "Hello world! (#{i})")
    end

    :ok = ExLibSRT.SRTLiveTransmit.close_stream(stream)

    for i <- 1..10 do
      assert_receive {:srt_data, ^conn_id, payload}, 500
      assert payload == "Hello world! (#{i})"
    end

    Transmit.stop_proxy(proxy)
  end

  test "can handle multiple connections", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    streams =
      for udp_port <- ctx.udp_port..(ctx.udp_port + 10), into: %{} do
        proxy = Transmit.start_streaming_proxy(udp_port, ctx.srt_port, "stream_#{udp_port}")

        assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000

        ExLibSRT.accept_awaiting_connect_request(server)

        assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

        stream = Transmit.start_stream(udp_port)

        {conn_id, %{stream: stream, proxy: proxy}}
      end

    for {conn_id, %{stream: stream}} <- streams do
      :ok = Transmit.send_payload(stream, "#{conn_id}")
      :ok = Transmit.close_stream(stream)
    end

    for {conn_id, %{stream: stream}} <- streams do
      payload = "#{conn_id}"
      assert_receive {:srt_data, ^conn_id, ^payload}, 500
    end
  end

  test "send closed connection notification", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    proxy =
      ExLibSRT.SRTLiveTransmit.start_streaming_proxy(
        ctx.udp_port,
        ctx.srt_port,
        "closing_stream_id"
      )

    assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
    ExLibSRT.accept_awaiting_connect_request(server)

    assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

    :ok = ExLibSRT.SRTLiveTransmit.stop_proxy(proxy)

    assert_receive {:srt_server_conn_closed, ^conn_id}, 2_000
  end

  test "close an ongoing connection", ctx do
    assert {:ok, server} = ExLibSRT.start_server("0.0.0.0", ctx.srt_port)

    _proxy =
      ExLibSRT.SRTLiveTransmit.start_streaming_proxy(
        ctx.udp_port,
        ctx.srt_port
      )

    assert_receive {:srt_server_connect_request, _address, _stream_id}, 2_000
    ExLibSRT.accept_awaiting_connect_request(server)

    assert_receive {:srt_server_conn, conn_id, _stream_id}, 1_000

    ExLibSRT.close_server_connection(conn_id, server)

    assert_receive {:srt_server_conn_closed, ^conn_id}, 1_000
  end

  defp prepare_file(ctx) do
    path = Path.join(ctx.tmp_dir, "#{System.unique_integer([:positive])}")

    file_size = Map.get(ctx, :file_size, 1024)

    content = :crypto.strong_rand_bytes(file_size)

    File.write!(path, content)

    [file_size: file_size, file_path: path, file_content: content]
  end

  defp prepare_streaming(_ctx) do
    udp_port = Enum.random(10_000..20_000)
    srt_port = Enum.random(10_000..20_000)

    [udp_port: udp_port, srt_port: srt_port]
  end
end
