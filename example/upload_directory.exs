Mix.install([
  :ex_aws,
  :ex_aws_s3,
  :hackney,
  :sweet_xml
])

defmodule ExampleS3 do
  @script_directory Path.dirname(__ENV__.file)

  @directory Path.join([@script_directory, "..", "test", "fixtures", "multiple-audios-and-videos"])

  @files File.ls!(@directory)
  @bucket System.fetch_env!("BUCKET_NAME")
  @output_path System.fetch_env!("REPORT_PATH")
  @hls_output_path System.fetch_env!("OUTPUT_DIRECTORY_PATH")

  @aws_config [
                access_key_id: System.fetch_env!("AWS_S3_ACCESS_KEY_ID"),
                secret_access_key: System.fetch_env!("AWS_S3_SECRET_ACCESS_KEY"),
                region: System.fetch_env!("AWS_S3_REGION")
              ]
              |> then(&ExAws.Config.new(:s3, &1))

  def upload_files() do
    Enum.each(@files, fn file ->
      file_path = @directory <> file

      file_path
      |> ExAws.S3.Upload.stream_file()
      |> ExAws.S3.upload(@bucket, @output_path <> file)
      |> ExAws.request(@aws_config)
    end)
  end

  def list_input_files() do
    @bucket
    |> ExAws.S3.list_objects(prefix: Path.dirname(@output_path))
    |> ExAws.request!(@aws_config)
    |> then(& &1.body.contents)
    |> Enum.map(& &1.key)
    |> IO.inspect(label: :UPLOADED_FILES)
  end

  def list_output_files() do
    @bucket
    |> ExAws.S3.list_objects(prefix: @hls_output_path)
    |> ExAws.request!(@aws_config)
    |> then(& &1.body.contents)
    |> Enum.map(& &1.key)
    |> IO.inspect(label: :HLS_UPLOADED_FILES)
  end

  def delete_files() do
    stream =
      @bucket
      |> ExAws.S3.list_objects(prefix: @hls_output_path)
      |> ExAws.stream!(@aws_config)
      |> Stream.map(& &1.key)

    @bucket
    |> ExAws.S3.delete_all_objects(stream)
    |> ExAws.request!(@aws_config)
  end
end

ExampleS3.list_input_files()

ExampleS3.list_output_files()
