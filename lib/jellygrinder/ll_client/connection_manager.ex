defmodule Jellygrinder.LLClient.ConnectionManager do
  @moduledoc false

  use GenServer

  defstruct [:conn, requests: %{}]

  @connection_opts [protocols: [:http2]]

  @spec start_link(URI.t()) :: GenServer.on_start()
  def start_link(uri) do
    GenServer.start_link(__MODULE__, uri)
  end

  @spec get(GenServer.server(), Path.t()) :: {:ok, map()} | {:error, term()}
  def get(pid, path) do
    GenServer.call(pid, {:get, path})
  end

  @impl true
  def init(uri) do
    case Mint.HTTP.connect(String.to_atom(uri.scheme), uri.host, uri.port, @connection_opts) do
      {:ok, conn} ->
        state = %__MODULE__{conn: conn}
        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:get, path}, from, state) do
    case Mint.HTTP.request(state.conn, "GET", path, [], "") do
      {:ok, conn, request_ref} ->
        state = put_in(state.requests[request_ref], %{from: from, response: %{}})
        {:noreply, %{state | conn: conn}}

      {:error, conn, reason} ->
        {:reply, {:error, reason}, %{state | conn: conn}}
    end
  end

  @impl true
  def handle_info(message, state) do
    case Mint.HTTP.stream(state.conn, message) do
      :unknown ->
        {:noreply, state}

      {:ok, conn, responses} ->
        state = Enum.reduce(responses, state, &process_response/2)
        {:noreply, %{state | conn: conn}}
    end
  end

  defp process_response({:status, request_ref, status}, state) do
    put_in(state.requests[request_ref].response[:status], status)
  end

  defp process_response({:headers, request_ref, headers}, state) do
    put_in(state.requests[request_ref].response[:headers], headers)
  end

  defp process_response({:data, request_ref, new_data}, state) do
    update_in(state.requests[request_ref].response[:data], fn data -> (data || "") <> new_data end)
  end

  defp process_response({:done, request_ref}, state) do
    {%{response: response, from: from}, state} = pop_in(state.requests[request_ref])
    GenServer.reply(from, {:ok, response})

    state
  end

  defp process_response({:error, request_ref, reason}, state) do
    {%{from: from}, state} = pop_in(state.requests[request_ref])
    GenServer.reply(from, {:error, reason})

    state
  end
end
