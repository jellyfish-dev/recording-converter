defmodule RecordingConverter.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions
  import Membrane.ChildrenSpec
  import Mox

  alias Membrane.AWS.S3.Source
  alias Membrane.Testing.{Pipeline, Sink}

  setup :verify_on_exit!
  setup :set_mox_from_context

  @fixtures "./test/fixtures/recording/"
  @audio "audio_220980017A897F34.msr"
  @video "video_3215165F9072CF66.msr"
  @report "report.json"
  @audio_path @fixtures <> @audio
  @video_path @fixtures <> @video
  @report_path @fixtures <> @report

  setup_all do
    bucket = Application.fetch_env!(:recording_converter, :bucket_name)

    input_dir_path = Application.fetch_env!(:recording_converter, :input_dir_path)
    output_dir_path = Application.fetch_env!(:recording_converter, :output_dir_path)
    %{bucket: bucket, input_dir_path: input_dir_path, output_path: output_dir_path}
  end

  setup state do
    Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

    on_exit(fn ->
      Application.delete_env(:ex_aws, :http_client)
    end)

    state
  end

  test "one audio, one video is correctly converted", %{
    bucket: bucket,
    input_dir_path: input_dir_path,
    output_path: output_dir_path
  } do
    files = %{
      @audio => File.read!(@audio_path),
      @video => File.read!(@video_path),
      @report => File.read!(@report_path)
    }

    setup_multipart_download_backend(bucket, input_dir_path, files)

    assert pipeline =
             Pipeline.start_link_supervised!(
               module: RecordingConverter.Pipeline,
               test_process: self()
             )

    monitor_ref = Process.monitor(pipeline)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, 5_000
  end

  defp setup_multipart_download_backend(
         bucket_name,
         dir_path,
         files
       ) do
    request_path = "https://s3.amazonaws.com/#{bucket_name}/#{dir_path}"

    stub(ExAws.Request.HttpMock, :request, fn
      :head, ^request_path <> file, _req_body, _headers, _http_opts ->
        file_body = Map.fetch!(files, file)

        content_length = file_body |> byte_size |> to_string

        {:ok, %{status_code: 200, headers: %{"Content-Length" => content_length}}}

      :get, ^request_path <> file, _req_body, headers, _http_opts ->
        file_body = Map.fetch!(files, file)
        headers = Map.new(headers)

        "bytes=" <> range = Map.fetch!(headers, "range")

        [first, second | _] = String.split(range, "-")

        first = String.to_integer(first)
        second = String.to_integer(second)

        <<_head::binary-size(first), payload::binary-size(second - first + 1), _rest::binary>> =
          file_body

        {:ok, %{status_code: 200, body: payload}}
    end)
  end
end
