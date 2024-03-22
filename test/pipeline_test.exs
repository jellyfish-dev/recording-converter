defmodule RecordingConverter.PipelineTest do
  use ExUnit.Case, async: false

  import Mox

  alias Membrane.Testing.Pipeline

  setup :verify_on_exit!
  setup :set_mox_from_context

  @fixtures "./test/fixtures"
  @input_request_path "https://s3.eu-central-1.amazonaws.com/bucket/test_path/"
  @index_name "index.m3u8"
  @wait_for_pipeline 30_000

  @type fallback_func_t :: (atom(), String.t(), map(), map(), Keyword.t() -> {atom(), map()})

  setup_all do
    bucket = Application.fetch_env!(:recording_converter, :bucket_name)

    report_path = Application.fetch_env!(:recording_converter, :report_path)
    output_dir_path = Application.fetch_env!(:recording_converter, :output_dir_path)
    compositor_path = Application.fetch_env!(:recording_converter, :compositor_path)

    %{
      bucket: bucket,
      report_path: report_path,
      output_path: output_dir_path,
      compositor_path: compositor_path
    }
  end

  setup state do
    File.rmdir(state.output_path)
    File.mkdir(state.output_path)

    Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

    on_exit(fn ->
      Application.delete_env(:ex_aws, :http_client)
      kill_compositor_process()
    end)

    state
  end

  test "one audio, one video is correctly converted",
       %{
         output_path: output_dir_path
       } = state do
    test_type = "/one-audio-one-video/"

    test_fixtures_path = @fixtures <> test_type

    files =
      test_fixtures_path
      |> File.ls!()
      |> Map.new(fn file_name ->
        {file_name, File.read!(test_fixtures_path <> file_name)}
      end)

    setup_multipart_download_backend(files, 10)

    pipeline = start_pipeline(state)

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    assert_pipeline_output(output_dir_path)
  end

  test "one audio is correctly converted",
       %{
         output_path: output_dir_path
       } = state do
    test_type = "/one-audio/"

    test_fixtures_path = @fixtures <> test_type

    files =
      test_fixtures_path
      |> File.ls!()
      |> Map.new(fn file_name ->
        {file_name, File.read!(test_fixtures_path <> file_name)}
      end)

    setup_multipart_download_backend(files, 4)

    pipeline = start_pipeline(state)

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    assert_pipeline_output(output_dir_path)
  end

  test "one video is correctly converted",
       %{
         output_path: output_dir_path
       } = state do
    test_type = "/one-video/"

    test_fixtures_path = @fixtures <> test_type

    files =
      test_fixtures_path
      |> File.ls!()
      |> Map.new(fn file_name ->
        {file_name, File.read!(test_fixtures_path <> file_name)}
      end)

    setup_multipart_download_backend(files, 8)

    pipeline = start_pipeline(state)

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    assert_pipeline_output(output_dir_path)
  end

  test "multiple audios, multiple videos is correctly converted",
       %{
         output_path: output_dir_path
       } = state do
    test_type = "/multiple-audios-and-videos/"

    test_fixtures_path = @fixtures <> test_type

    files =
      test_fixtures_path
      |> File.ls!()
      |> Map.new(fn file_name ->
        {file_name, File.read!(test_fixtures_path <> file_name)}
      end)

    setup_multipart_download_backend(files, 18)

    pipeline = start_pipeline(state)

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    assert_pipeline_output(output_dir_path)
  end

  @spec request_handler(
          files :: [String.t()],
          fallback :: nil | fallback_func_t()
        ) :: {atom(), map()}
  def request_handler(files, fallback \\ nil) do
    pid = self()

    fn
      :head, @input_request_path <> file, _req_body, _headers, _http_opts ->
        assert {:ok, file_body} = Map.fetch(files, file)

        send(pid, :received_head)

        content_length = file_body |> byte_size |> to_string

        {:ok, %{status_code: 200, headers: %{"Content-Length" => content_length}}}

      :get, @input_request_path <> file, _req_body, headers, _http_opts ->
        file_body = Map.fetch!(files, file)
        headers = Map.new(headers)

        "bytes=" <> range = Map.fetch!(headers, "range")

        [first, second | _] = String.split(range, "-")

        first = String.to_integer(first)
        second = String.to_integer(second)

        <<_head::binary-size(first), payload::binary-size(second - first + 1), _rest::binary>> =
          file_body

        {:ok, %{status_code: 200, body: payload}}

      method, request_path, req_body, headers, http_opts when not is_nil(fallback) ->
        fallback.(method, request_path, req_body, headers, http_opts)
    end
  end

  @spec assert_pipeline_output(String.t()) :: no_return()
  def assert_pipeline_output(output_dir_path) do
    index_file = assert_file_exist!(@index_name, output_dir_path)

    playlist_name =
      index_file
      |> String.split("\n")
      |> Enum.at(-1)

    playlist_file = assert_file_exist!(playlist_name, output_dir_path)

    playlist_lines = String.split(playlist_file, "\n")

    playlist_lines
    |> Stream.filter(&String.contains?(&1, "muxed_header"))
    |> Stream.map(&String.replace(&1, "#EXT-X-MAP:URI=", ""))
    |> Enum.map(&String.replace(&1, "\"", ""))
    |> assert_files_exist!(output_dir_path)

    playlist_lines
    |> Enum.filter(&String.starts_with?(&1, "muxed_segment"))
    |> assert_files_exist!(output_dir_path)
  end

  defp assert_files_exist!(files, dir_path) when is_list(files) do
    Enum.each(files, &assert_file_exist!(&1, dir_path))
  end

  defp assert_file_exist!(file, dir_path) when is_binary(file) do
    file_path = dir_path <> file
    {result, file} = File.read(file_path)

    assert(
      result == :ok,
      "File that doesn't exists: #{file_path}"
    )

    assert byte_size(file) > 0
    file
  end

  defp setup_multipart_download_backend(files, nums) do
    request_handler = request_handler(files)

    expect(ExAws.Request.HttpMock, :request, nums, request_handler)
  end

  defp start_pipeline(state) do
    assert pipeline =
             Pipeline.start_link_supervised!(
               module: RecordingConverter.Pipeline,
               test_process: self(),
               custom_args: %{
                 bucket_name: state.bucket,
                 s3_directory: Path.dirname(state.report_path),
                 output_directory:
                   if(String.starts_with?(state.output_path, "."),
                     do: "test_path/output",
                     else: "test_path/"
                   ),
                 compositor_path: state.compositor_path
               }
             )

    pipeline
  end

  defp kill_compositor_process() do
    port = 8081

    command = "lsof -i tcp:#{port} | grep LISTEN | awk '{print $2}' | xargs kill -9"
    :os.cmd(String.to_charlist(command))
  end
end
