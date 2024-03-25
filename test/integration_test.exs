defmodule RecordingConverter.RecordingTest do
  use ExUnit.Case

  import Mox

  alias RecordingConverter.PipelineTest

  setup :set_mox_from_context
  setup :verify_on_exit!

  @upload_id "upload_id"
  @etag 1
  @bucket_request_path "https://s3.eu-central-1.amazonaws.com/bucket/"
  @index_paths ["output/index.m3u8", "test_path/output/index.m3u8"]
  @wait_for_pipeline 30_000

  setup_all do
    bucket = Application.fetch_env!(:recording_converter, :bucket_name)

    report_path = Application.fetch_env!(:recording_converter, :report_path)
    output_dir_path = Application.fetch_env!(:recording_converter, :output_dir_path)

    %{bucket: bucket, report_path: report_path, output_path: output_dir_path}
  end

  setup state do
    kill_compositor_process()

    File.rmdir(state.output_path)
    File.mkdir(state.output_path)

    Application.put_env(:recording_converter, :output_dir_path, state.output_path)
    Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

    on_exit(fn ->
      Application.delete_env(:ex_aws, :http_client)
      Application.put_env(:recording_converter, :output_dir_path, state.output_path)
      kill_compositor_process()
    end)

    state
  end

  test "one audio, one video is correctly converted", %{
    bucket: bucket,
    report_path: report_path,
    output_path: output_dir_path
  } do
    setup_terminator()
    test_type = "/one-audio-one-video/"

    files = PipelineTest.get_files(test_type)

    setup_multipart_download_backend(bucket, report_path, output_dir_path, files, 26)

    {:ok, pid} = RecordingConverter.start()

    monitor_ref = Process.monitor(pid)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    PipelineTest.assert_pipeline_output(output_dir_path)

    assert_received :terminated
  end

  test "output_path is relative", %{
    bucket: bucket,
    report_path: report_path,
    output_path: output_dir_path
  } do
    setup_terminator()
    output_dir_path = "./#{output_dir_path}"

    Application.put_env(:recording_converter, :output_dir_path, output_dir_path)

    test_type = "/one-audio-one-video/"

    files = PipelineTest.get_files(test_type)

    setup_multipart_download_backend(
      bucket,
      report_path,
      "test_path/output",
      files,
      26
    )

    {:ok, pid} = RecordingConverter.start()

    monitor_ref = Process.monitor(pid)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :normal}, @wait_for_pipeline

    PipelineTest.assert_pipeline_output("test_path/output/")

    assert_received :terminated
  end

  test "uploading to s3 failed", %{
    output_path: output_dir_path
  } do
    setup_terminator(1)
    test_type = "/one-audio-one-video/"

    files = PipelineTest.get_files(test_type)

    setup_s3_upload_failure(files)

    {:ok, pid} = RecordingConverter.start()

    monitor_ref = Process.monitor(pid)

    assert_receive {:DOWN, ^monitor_ref, :process, _pipeline_pid, :error}, @wait_for_pipeline

    PipelineTest.assert_pipeline_output(output_dir_path)

    assert_received :terminated
  end

  defp setup_terminator(expected_status_code \\ 0) do
    pid = self()

    expect(RecordingConverter.TerminatorMock, :terminate, 1, fn status_code ->
      assert expected_status_code == status_code
      send(pid, :terminated)
    end)

    Process.sleep(100)
  end

  defp setup_multipart_download_backend(
         bucket_name,
         dir_path,
         output_path,
         files,
         request_nums
       ) do
    output_prefix = output_path |> String.replace_suffix("/", "")

    pid = self()

    {:ok, agent} = Agent.start(fn -> [] end)

    request_handler =
      PipelineTest.request_handler(files, fn
        :post, @bucket_request_path <> _rest, <<>>, _headers, _http_opts ->
          send(pid, :upload_initialized)

          {:ok,
           %{
             status_code: 200,
             body: """
             <InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
               <Bucket>#{bucket_name}</Bucket>
               <Key>#{dir_path}</Key>
               <UploadId>#{@upload_id}</UploadId>
             </InitiateMultipartUploadResult>
             """
           }}

        :post, @bucket_request_path <> file_name, _body, _headers, _http_opts ->
          send(pid, :upload_completed)

          file_name =
            file_name
            |> String.replace_suffix("?uploadId=#{@upload_id}", "")

          Agent.update(agent, &[file_name | &1])

          {:ok,
           %{
             status_code: 200,
             body: """
             <CompleteMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
               <Location>https://s3-eu-west-1.amazonaws.com/#{bucket_name}/#{dir_path}</Location>
               <Bucket>#{bucket_name}</Bucket>
               <Key>#{dir_path}</Key>
               <ETag>&quot;17fbc0a106abbb6f381aac6e331f2a19-1&quot;</ETag>
             </CompleteMultipartUploadResult>
             """
           }}

        :put, @bucket_request_path <> index_file, _body, _headers, _http_opts
        when index_file in @index_paths ->
          send(pid, :index_uploaded)

          {:ok, %{status_code: 200}}

        :put, @bucket_request_path <> _file_name, _body, _headers, _http_opts ->
          send(pid, :chunk_uploaded)

          {:ok,
           %{
             status_code: 200,
             headers: %{"ETag" => @etag}
           }}

        :get, @bucket_request_path <> _rest, _body, _headers, _http_opts ->
          contents =
            agent
            |> Agent.get(& &1)
            |> Enum.map_join(fn file ->
              """
              <Contents>
              <Key>#{file}</Key>
              <LastModified>2011-02-26T01:56:20.000Z</LastModified>
              <Size>142863</Size>
              <Owner>
              <ID>canonical-user-id</ID>
              <DisplayName>display-name</DisplayName>
              </Owner>
              <StorageClass>STANDARD</StorageClass>
              </Contents>
              """
            end)

          body = """
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
          <Name>#{bucket_name}</Name>
          <Prefix>#{output_prefix}</Prefix>
          <Marker></Marker>
          <MaxKeys>1000</MaxKeys>
          <Delimiter>/</Delimiter>
          <IsTruncated>false</IsTruncated>
          #{contents}
          <CommonPrefixes>
          </CommonPrefixes>
          </ListBucketResult>
          """

          {:ok, %{status_code: 200, body: body}}
      end)

    expect(ExAws.Request.HttpMock, :request, request_nums, request_handler)
    Process.sleep(100)
  end

  defp setup_s3_upload_failure(files) do
    request_handler =
      PipelineTest.request_handler(files, fn _method, _path, _body, _headers, _opts ->
        {:ok, %{status_code: 401}}
      end)

    expect(ExAws.Request.HttpMock, :request, 14, request_handler)

    Process.sleep(100)
  end

  defp kill_compositor_process() do
    port = 8081

    command = "lsof -i tcp:#{port} | grep LISTEN | awk '{print $2}' | xargs kill -9"
    System.cmd("sh", ["-c", command])
  end
end
