defmodule RecordingConverter do
  @moduledoc false
  use GenServer
  require Logger

  alias ExAws.S3

  @index_file "index.m3u8"

  @spec compositor_path() :: binary() | nil
  def compositor_path() do
    Application.fetch_env!(:recording_converter, :compositor_path)
  end

  @spec bucket_name() :: binary()
  def bucket_name() do
    Application.fetch_env!(:recording_converter, :bucket_name)
  end

  @spec output_directory() :: binary()
  def output_directory() do
    Application.fetch_env!(:recording_converter, :output_dir_path)
  end

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @spec start(list()) :: GenServer.on_start()
  def start(args \\ []) do
    GenServer.start(__MODULE__, args)
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
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, :normal}, state) do
    with :ok <- send_files_without_index(),
         {:ok, objects} <- get_bucket_objects(),
         objects <- fetch_bucket_objects_name(objects),
         true <- check_s3_bucket_and_local_equals?([@index_file | objects]),
         {:ok, _value} <- send_file(@index_file) do
      terminate(0)
      {:stop, :normal, state}
    else
      _any_error ->
        terminate(1)
        {:stop, :error, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, reason}, state) do
    Logger.warning("Recording Converter pipeline is down with reason: #{inspect(reason)}")
    # terminate(1)
    {:stop, :error, state}
  end

  defp send_files_without_index() do
    {_succeses, failures} =
      output_directory()
      |> File.ls!()
      |> Enum.reject(&String.ends_with?(&1, @index_file))
      |> Enum.map(&send_file(&1))
      |> Enum.split_with(fn
        {:ok, _value} -> true
        {:error, _any} -> false
      end)

    if Enum.empty?(failures) do
      :ok
    else
      Enum.each(failures, fn {:error, error} ->
        Logger.error("Request failed info: #{inspect(error)}")
      end)

      :error
    end
  end

  defp get_bucket_objects() do
    bucket_name()
    |> S3.list_objects(prefix: output_directory())
    |> ExAws.request()
  end

  defp fetch_bucket_objects_name(objects) do
    objects
    |> Map.fetch!(:body)
    |> Map.fetch!(:contents)
    |> Enum.map(&Map.fetch!(&1, :key))
  end

  defp check_s3_bucket_and_local_equals?(objects) do
    output_directory() |> File.ls!() |> MapSet.new() == objects |> MapSet.new()
  end

  defp send_file(file_name) do
    bucket = bucket_name()
    file_path = output_directory() <> file_name

    file_path
    |> S3.Upload.stream_file()
    |> S3.upload(bucket, file_path)
    |> ExAws.request()
  end

  defp terminate(status_code) do
    Application.fetch_env!(:recording_converter, :terminator).terminate(status_code)
  end
end
