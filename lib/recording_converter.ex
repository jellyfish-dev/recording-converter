defmodule RecordingConverter do
  require Logger
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{}, {:continue, nil}}
  end

  @impl true
  def handle_continue(_continue_arg, state) do
    {:ok, _supervisor, pipeline_pid} = Membrane.Pipeline.start(RecordingConverter.Pipeline, [])

    Process.monitor(pipeline_pid)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, :normal}, _state) do
    System.stop(0)
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, reason}, _state) do
    Logger.warning("Recording Converter pipeline is down with reason: #{reason}")
    System.stop(1)
  end
end
