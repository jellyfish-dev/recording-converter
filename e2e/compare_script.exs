Mix.install([
  :ex_aws,
  :ex_aws_s3,
  :hackney,
  :sweet_xml
])

defmodule CompareScript do
  @bucket "bucket"
  @index_name "index.m3u8"
  @aws_config [
                access_key_id: System.get_env("AWS_S3_ACCESS_KEY_ID", "dummy"),
                secret_access_key: System.get_env("AWS_S3_SECRET_ACCESS_KEY", "dummy"),
                region: System.get_env("AWS_S3_REGION", "us-east-1"),
                scheme: "http://",
                host: "s3mock",
                port: 4566
              ]
              |> then(&ExAws.Config.new(:s3, &1))

  def list_output_files(hls_output_path) do
    @bucket
    |> ExAws.S3.list_objects(prefix: hls_output_path)
    |> ExAws.request!(@aws_config)
    |> then(& &1.body.contents)
    |> Enum.map(& &1.key)
  end

  def download_output_files(output_dir) do
    hls_output_path = System.fetch_env!("TEST_NAME") |> Path.join("output")
    output_files = list_output_files(hls_output_path)

    Enum.each(output_files, fn file ->
      dest_file = Path.join(output_dir, file)

      dest_file
      |> Path.dirname()
      |> File.mkdir_p!()

      @bucket
      |> ExAws.S3.download_file(file, dest_file)
      |> ExAws.request!(@aws_config)
    end)
  end

  def hash_file(file_path) do
    File.stream!(file_path)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
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
    file_path = Path.join([".", dir_path, file])
    {result, file} = File.read(file_path)

    dir_files = File.ls!(dir_path) |> Enum.join(" ")
    local_files = File.ls!("./") |> Enum.join(" ")

    assert(
      result == :ok,
      "File that doesn't exists: #{file_path},\n dir/files (#{dir_path}): #{dir_files},\n ./files: #{local_files}"
    )

    assert(byte_size(file) > 0, "File #{file_path} has size not bigger than 0")
    file
  end

  defp assert(condition, text) do
    unless condition do
      IO.inspect(text)
      System.stop(1)
    end
  end
end

output_dir = "./example-output/"
CompareScript.download_output_files(output_dir)

test_name = System.fetch_env!("TEST_NAME")

output_dir = Path.join([output_dir, test_name, "output"])

CompareScript.assert_pipeline_output(output_dir)
