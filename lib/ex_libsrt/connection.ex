defmodule ExLibSRT.Connection do
  @moduledoc """
  Server connection.
  """
  use GenServer

  @type t :: GenServer.server()

  defmodule Handler do
    @moduledoc """
    Handler behaviour for incoming connection messages.
    """

    @type t :: module() | struct()

    @type connection_id :: non_neg_integer()
    @type stream_id :: String.t()

    @type state :: any()

    @callback init(t()) :: state()

    @doc """
    Invoked when a connection gets fully established.
    """
    @callback handle_connected(connection_id(), stream_id(), state()) :: {:ok, state} | :stop

    @doc """
    Invoked when a connection gets disconnected .
    """
    @callback handle_disconnected(state) :: :ok

    @doc """
    Invoked when a new payload arrives. 
    """
    @callback handle_data(binary(), state()) :: {:ok, state} | :stop
  end

  @spec start(Handler.t()) :: GenServer.on_start()
  def start(handler) do
    GenServer.start(__MODULE__, handler, [])
  end

  @spec stop(t()) :: GenServer.on_stop()
  def stop(handler) do
    GenServer.stop(handler)
  end

  @impl true
  def init(handler) do
    {state, mod} =
      case handler do
        %mod{} ->
          {mod.init(handler), mod}

        handler ->
          {handler.init(handler), handler}
      end

    {:ok, %{handler: mod, handler_state: state}}
  end

  @impl true
  def handle_info({:srt_data, _conn_id, data}, state) do
    case state.handler.handle_data(data, state.handler_state) do
      {:ok, handler_state} ->
        {:noreply, %{state | handler_state: handler_state}}

      :stop ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:srt_server_conn, conn, stream_id}, state) do
    case state.handler.handle_connected(conn, stream_id, state.handler_state) do
      {:ok, handler_state} ->
        {:noreply, %{state | handler_state: handler_state}}

      :stop ->
        {:stop, :normal, state}
    end
  end

  @impl true
  def handle_info({:srt_server_conn_closed, _conn}, state) do
    :ok = state.handler.handle_disconnected(state.handler_state)

    {:stop, :normal, state}
  end
end
