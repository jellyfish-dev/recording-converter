Mix.install([
  :ex_aws,
  :ex_aws_s3,
  :hackney,
  :sweet_xml
])

defmodule CompareScript do
  @bucket "bucket"
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
    |> IO.inspect(label: :HLS_UPLOADED_FILES)
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
end

output_dir = "./example-output/"
CompareScript.download_output_files(output_dir)

test_name = System.fetch_env!("TEST_NAME")

output_dir = Path.join([output_dir, test_name, "output"])

output_hashes =
  output_dir
  |> File.ls!()
  |> Enum.map(&Path.join(output_dir, &1))
  |> Map.new(&{&1, CompareScript.hash_file(&1)})
  |> IO.inspect(label: :WTF)

reference_hashes = %{
  "./example-output/one-video/output/g3cFdmlkZW8.m3u8" =>
    "a03b3caab7e92232dced4baa8f659808f520f37768084070505ed1090536d914",
  "./example-output/one-video/output/index.m3u8" =>
    "e43fef97f7cc8755273b413a70dce4554d1827afe7df072f12b3524860c26e16",
  "./example-output/one-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
    "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
  "./example-output/one-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
    "40c1f6e975e51374cc102551aa8c4467d4761e9d20ca95fc690487291c925a39",
  "./example-output/one-video/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
    "dd35d7b6d03b73ed65aafaf3b47549de20f4a0685be001e294293a33ffbbfc26"
}

Enum.each(output_hashes, fn {file_path, file_hash} ->
  if Map.fetch!(reference_hashes, file_path) != file_hash do
    System.stop(1)
  end
end)
