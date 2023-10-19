defmodule Jellygrinder.Coordinator do
  @moduledoc false

  use GenServer, restart: :temporary

  require Logger

  alias Jellygrinder.Client.{HLS, LLHLS}
  alias Jellygrinder.ClientSupervisor
  alias Jellygrinder.Coordinator.Config

  @spec run_test(Config.t()) :: :ok | no_return()
  def run_test(config) do
    ref = Process.monitor(__MODULE__)
    GenServer.call(__MODULE__, {:run_test, config})

    receive do
      {:DOWN, ^ref, :process, _pid, reason} ->
        if reason != :normal,
          do: Logger.error("Coordinator process exited with reason #{inspect(reason)}")

        :ok
    end
  end

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_args) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    Logger.info("Coordinator: Init (pid: #{inspect(self())})")

    {:ok, nil}
  end

  @impl true
  def handle_call({:run_test, config}, _from, _state) do
    config = Config.fill_hls_url!(config)

    Logger.info("""
    Coordinator: Start of test
      URL: #{config.url}
      Clients: #{config.clients}
      Time: #{config.time} s
      Spawn interval: #{config.spawn_interval} ms
      Save results to: #{config.out_path}
    """)

    Process.send_after(self(), :end_test, config.time * 1000)
    send(self(), :spawn_client)

    state = %{
      uri: URI.parse(config.url),
      clients: %{max: config.clients, spawned: 0, alive: 0},
      time: config.time,
      spawn_interval: config.spawn_interval,
      out_path: config.out_path,
      ll_hls?: config.ll_hls,
      results: []
    }

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:result, r}, %{results: results} = state) do
    r = amend_result(r, state)

    unless r.success do
      Logger.warning(
        "Coordinator: Request failed (from: #{r.process_name}, label: #{r.label}, code: #{r.response_code}, reason: #{r.failure_msg})"
      )
    end

    {:noreply, %{state | results: [r | results]}}
  end

  @impl true
  def handle_info(:spawn_client, %{clients: %{max: max, spawned: max}} = state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:spawn_client, %{clients: clients, ll_hls?: ll_hls?} = state) do
    Process.send_after(self(), :spawn_client, state.spawn_interval)
    name = "client-#{clients.spawned + 1}"

    client = if ll_hls?, do: LLHLS, else: HLS

    case ClientSupervisor.spawn_client(client, %{uri: state.uri, name: name}) do
      {:ok, pid} ->
        Logger.info("Coordinator: #{name} spawned at #{inspect(pid)}")
        _ref = Process.monitor(pid)

        clients =
          clients
          |> Map.update!(:spawned, &(&1 + 1))
          |> Map.update!(:alive, &(&1 + 1))

        {:noreply, %{state | clients: clients}}

      {:error, reason} ->
        Logger.error("Coordinator: Error spawning #{name}: #{inspect(reason)}")

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(:end_test, %{results: results, out_path: out_path} = state) do
    Logger.info("Coordinator: End of test")

    ClientSupervisor.terminate()

    Logger.info("Coordinator: Generating report...")

    results =
      results
      |> Enum.reverse()
      |> Enum.map_join("", &serialize_result/1)

    Logger.info("Coordinator: Saving generated report to #{out_path}...")
    File.write!(out_path, results_header() <> results)
    Logger.info("Coordinator: Report saved successfully. Exiting")

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{clients: clients} = state) do
    Logger.warning("Coordinator: Child process #{inspect(pid)} died: #{inspect(reason)}")

    clients = Map.update!(clients, :alive, &(&1 - 1))

    {:noreply, %{state | clients: clients}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Coordinator: Received unexpected message: #{inspect(msg)}")

    {:noreply, state}
  end

  defp amend_result(result, %{clients: %{alive: client_count}, uri: uri} = _state) do
    request_url = uri |> Map.put(:path, result.path) |> URI.to_string()

    result
    |> Map.put(:client_count, client_count)
    |> Map.put(:url, request_url)
  end

  defp results_header() do
    """
    timeStamp,elapsed,label,responseCode,responseMessage,threadName,dataType,success,\
    failureMessage,bytes,sentBytes,grpThreads,allThreads,URL,Latency,IdleTime,Connect
    """
  end

  defp serialize_result(r) do
    """
    #{r.timestamp},#{r.elapsed},#{r.label},#{r.response_code},,#{r.process_name},,#{r.success},\
    #{csv_safe(r.failure_msg)},#{r.bytes},-1,#{r.client_count},#{r.client_count},#{r.url},-1,-1,-1
    """
  end

  defp csv_safe(string) do
    String.replace(string, [",", "\n", "\r"], ";")
  end
end
