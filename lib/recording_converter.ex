defmodule RecordingConverter do
  @moduledoc false
  use GenServer
  require Logger

  alias ExAws.S3

  @index_file "index.m3u8"

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
    {:ok, _supervisor, pipeline_pid} =
      Membrane.Pipeline.start(RecordingConverter.Pipeline, %{
        bucket_name: bucket_name(),
        compositor_path: compositor_path(),
        s3_directory: s3_directory(),
        output_directory: output_directory(),
        image_url: image_url()
      })

    Process.monitor(pipeline_pid)

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, :normal}, state) do
    with :ok <- send_files_without_index(),
         {:ok, _value} <- send_file(@index_file) do
      terminate(0)
      {:stop, :normal, state}
    else
      error ->
        Logger.error("Received error: #{inspect(error)}")
        terminate(1)
        {:stop, :error, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _monitor, :process, _pipeline_pid, reason}, state) do
    Logger.warning("Recording Converter pipeline is down with reason: #{inspect(reason)}")
    terminate(1)
    {:stop, :error, state}
  end

  defp send_files_without_index() do
    local_files = get_local_files_without_index()

    Logger.info("Files to send: #{Enum.join(local_files, " ")}")

    {_succeses, failures} =
      local_files
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

  defp get_local_files_without_index() do
    output_directory()
    |> File.ls!()
    |> Enum.reject(&String.ends_with?(&1, @index_file))
  end

  defp send_file(file_name) do
    bucket = bucket_name()
    file_path = Path.join(output_directory(), file_name)

    result =
      file_path
      |> S3.Upload.stream_file()
      |> S3.upload(bucket, file_path)
      |> ExAws.request()

    Logger.info("Send file #{file_path} to remote_path: #{file_path}, result: #{inspect(result)}")

    result
  end

  defp terminate(status_code) do
    Application.fetch_env!(:recording_converter, :terminator).terminate(status_code)
  end

  defp compositor_path() do
    Application.fetch_env!(:recording_converter, :compositor_path)
  end

  defp bucket_name() do
    Application.fetch_env!(:recording_converter, :bucket_name)
  end

  defp s3_directory() do
    report_path = Application.fetch_env!(:recording_converter, :report_path)
    Path.dirname(report_path)
  end

  defp output_directory() do
    output_directory = Application.fetch_env!(:recording_converter, :output_dir_path)

    if String.starts_with?(output_directory, ".") do
      output_directory =
        output_directory
        |> Path.split()
        |> Enum.drop(1)
        |> Path.join()

      "#{s3_directory()}/#{output_directory}"
    else
      output_directory
    end
  end

  defp image_url() do
    Application.fetch_env!(:recording_converter, :image_url)
  end
end
