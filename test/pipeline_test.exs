defmodule RecordingConverter.PipelineTest do
  use ExUnit.Case

  import Mox

  alias Membrane.Testing.Pipeline

  setup :verify_on_exit!
  setup :set_mox_from_context

  @referals "./test/fixtures/referals/"
  @fixtures "./test/fixtures/recording/"
  @audio "audio_FC45E6CF26C7683C.msr"
  @video "video_15D5A19A045095D9.msr"
  @report "report.json"
  @audio_path @fixtures <> @audio
  @video_path @fixtures <> @video
  @report_path @fixtures <> @report
  @input_request_path "https://s3.amazonaws.com/bucket/test_path/"

  setup_all do
    bucket = Application.fetch_env!(:recording_converter, :bucket_name)

    input_dir_path = Application.fetch_env!(:recording_converter, :input_dir_path)
    output_dir_path = Application.fetch_env!(:recording_converter, :output_dir_path)
    %{bucket: bucket, input_dir_path: input_dir_path, output_path: output_dir_path}
  end

  setup state do
    File.rmdir(state.output_path)
    File.mkdir(state.output_path)

    Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

    on_exit(fn ->
      Application.delete_env(:ex_aws, :http_client)
    end)

    state
  end

  test "one audio, one video is correctly converted", %{
    output_path: output_dir_path
  } do
    files = %{
      @audio => File.read!(@audio_path),
      @video => File.read!(@video_path),
      @report => File.read!(@report_path)
    }

    setup_multipart_download_backend(files)

    assert pipeline =
             Pipeline.start_link_supervised!(
               module: RecordingConverter.Pipeline,
               test_process: self()
             )

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, 10_000

    assert_pipeline_output(@referals, output_dir_path)
  end

  def request_handler(files, fallback \\ nil) do
    fn
      :head, @input_request_path <> file, _req_body, _headers, _http_opts ->
        file_body = Map.fetch!(files, file)

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

  def assert_pipeline_output(referals_path, output_dir_path) do
    referals = File.ls!(referals_path)

    output = File.ls!(output_dir_path)

    assert referals == output

    referals
    |> Enum.zip(output)
    |> Enum.each(fn {referal, output} ->
      assert referal == output

      referal_file = File.read!(@referals <> referal)
      output_file = File.read!(output_dir_path <> output)

      referal_size = byte_size(referal_file)

      # assert referal_file == output_file
      assert byte_size(referal_file) <= byte_size(output_file)

      unless ignore_file?(referal),
        do: assert(referal_file == binary_slice(output_file, 0, referal_size))
    end)
  end

  defp ignore_file?(file_name) do
    String.contains?(file_name, "muxed_segment_1") or file_name == "g3cFdmlkZW8.m3u8" or
      file_name == "index.m3u8"
  end

  defp setup_multipart_download_backend(files) do
    request_handler = request_handler(files)

    expect(ExAws.Request.HttpMock, :request, 10, request_handler)
  end
end
