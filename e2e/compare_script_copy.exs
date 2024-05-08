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

# output_hashes =
#   output_dir
#   |> File.ls!()
#   |> Enum.map(&Path.join(output_dir, &1))
#   |> Map.new(&{&1, CompareScript.hash_file(&1)})
#   |> IO.inspect(label: :WTF)

# reference_hashes = %{
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/g3cFdmlkZW8.m3u8" =>
#     "ca805d4ad2e7e2b84dca2bb3e91e80158afab2b57dc705608fe4ab6e4555f47d",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/index.m3u8" =>
#     "97d790f8a2830a2289b16262c83dd3c9bf3a5006dba27ea20a444fe0e5bdeedb",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "b2cfba583487b3c5e901681a0c8cf5c54bb2a6792878401b892f40876c5510e0",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "140b4f85165d88699c83d36a5d9cb7ed2adf6aca3700b1a3044ee093a0cb832b",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "23a81083df593c743cd0b5fd2fdfb0cdd711b601e0bdcbf873fac94cc0059832",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_3_g3cFdmlkZW8.m4s" =>
#     "228ad0a63742602e29c1551d379ff29405361740a23946f04e82069b955960b1",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_4_g3cFdmlkZW8.m4s" =>
#     "bc115c0882128fd7ef2ef2ff556af2948f9b8d32cfb4f295b7fcc21ceee66953",
#   "./example-output/first-only-audio-second-only-video-third-audio-and-video/output/muxed_segment_5_g3cFdmlkZW8.m4s" =>
#     "19cb8cf672ec21e5391ea485d8e1f5544d5dac86be5c3982a0dcef9f96ea049e",
#   "./example-output/grid-limits/output/g3cFdmlkZW8.m3u8" =>
#     "c463ddaea2371b90953180962c068f465cba7fc94ca7d0211e3620e61043c32a",
#   "./example-output/grid-limits/output/index.m3u8" =>
#     "3fcc61a34987651edc1850006d6c496eb15723a4e08ff1cc2a0736bc94ecf70a",
#   "./example-output/grid-limits/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/grid-limits/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "97cc40fb7688096b3040615ef589d5114ba74b1cb1eecb6876b3b7a22d61dd0e",
#   "./example-output/grid-limits/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "b66cc418be904c7e26fcfea86225fff8cec20be2a91f82f07e62fddf796cbac4",
#   "./example-output/grid-limits/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "14a66c1eaa10bda9a801928327975b0ad1f1ede28f45fd0e019ae7859e4044ab",
#   "./example-output/grid-limits/output/muxed_segment_3_g3cFdmlkZW8.m4s" =>
#     "34b1bafc3a4205d77f7b0b72ca77b1f7b8dba7d2d8b25f4fa4b40c7896eb5358",
#   "./example-output/grid-limits/output/muxed_segment_4_g3cFdmlkZW8.m4s" =>
#     "52d3a491113f1f5d0eb682d96cede779735058b9b5bc6c21e50d2b5199833c2d",
#   "./example-output/long-video/output/g3cFdmlkZW8.m3u8" =>
#     "05c12ee1c4e06b26ad800493c8ec807881a2bf9c48b39fd985e9d36991744b4e",
#   "./example-output/long-video/output/index.m3u8" =>
#     "bb1e0fff0b96efcb32f3029e6e366732bf0b467cf20aad523065437e052aa7c1",
#   "./example-output/long-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/long-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "7791926c42e49f1329c549b03a85e5ef96678d2127f42c35fb3d476ff696c60d",
#   "./example-output/long-video/output/muxed_segment_10_g3cFdmlkZW8.m4s" =>
#     "97d1c4c3f178106f127f57a05e28b43c1ab5a2834088ebdea05e03fd5a6195f5",
#   "./example-output/long-video/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "af2e2ec6e9d971cc9dcb38983eee8a8d737c9925daf796adb9f5790993880799",
#   "./example-output/long-video/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "5c629ccb1e5600e594e0675285c5c5999c01f425e5c278c36d21ee214747ed8e",
#   "./example-output/long-video/output/muxed_segment_3_g3cFdmlkZW8.m4s" =>
#     "bf7b2805b12a4943dd87fb6403beb051b2054060b7f5285e9205f2b96ac2edd5",
#   "./example-output/long-video/output/muxed_segment_4_g3cFdmlkZW8.m4s" =>
#     "886ff208eb1d64ac461b111719c9e0a5b3427fc6393005035f2a3e4d35329ffe",
#   "./example-output/long-video/output/muxed_segment_5_g3cFdmlkZW8.m4s" =>
#     "fbd8d205cbbe8a5fa38b4fc3cf767ff0a04edd8f7c35a5ecc6578ea395756197",
#   "./example-output/long-video/output/muxed_segment_6_g3cFdmlkZW8.m4s" =>
#     "9a92af619c3b32e039f103a423ef45724e7cec86f887cbd68973c2b2e5f8a0e1",
#   "./example-output/long-video/output/muxed_segment_7_g3cFdmlkZW8.m4s" =>
#     "4bb3b93650d216a85a6586117b40181f4cdf6e45a4c99df651727e3144d77d0e",
#   "./example-output/long-video/output/muxed_segment_8_g3cFdmlkZW8.m4s" =>
#     "a2736c95f8f75dc1be298e7a8f79894fa8276fd6ef43e8773c0df742ec553190",
#   "./example-output/long-video/output/muxed_segment_9_g3cFdmlkZW8.m4s" =>
#     "51ccc1080ee23ee36eb9393e90a53c9bd7704b1fb82776f484681af8abbfff24",
#   "./example-output/multiple-audios-and-one-video/output/g3cFdmlkZW8.m3u8" =>
#     "06b231df21e1f9946af0371a84eba17f4fa328ffd467b7782e57c144698b9ab7",
#   "./example-output/multiple-audios-and-one-video/output/index.m3u8" =>
#     "0272fa0c5d6590058c88a3b6cd1d7264a4f33ec1729eaa336b43d12551aa506c",
#   "./example-output/multiple-audios-and-one-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/multiple-audios-and-one-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "0ed031c8c6e7cf23bfe587ea23e98b778476b66c243412f69190df565eaf6358",
#   "./example-output/multiple-audios-and-videos/output/g3cFdmlkZW8.m3u8" =>
#     "8377780091f8c5d3b7dd4ec6e3160f29c7d41f245ff544c2b2652475d3f93833",
#   "./example-output/multiple-audios-and-videos/output/index.m3u8" =>
#     "e319b1b353732a29fd3f4b8afa4598a1c0583837f9d4c1bd701220066a7530b7",
#   "./example-output/multiple-audios-and-videos/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/multiple-audios-and-videos/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "b169b4013a0fae06c043ad42baab378de76d24bf0116d10301a539be9ec6340a",
#   "./example-output/multiple-audios-and-videos/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "c4782511ca87b7901918a99b99bb9fadf58377f8c207321be3a0792464d2115a",
#   "./example-output/one-audio/output/g3cFdmlkZW8.m3u8" =>
#     "4ead34bb8176eaf176c3fcebb13738cd0c184fc2688f4f5194f608068d356503",
#   "./example-output/one-audio/output/index.m3u8" =>
#     "fc786251f68f4a1d84b829969c60bf5592c1fd78844e3e17096de987be6cd82f",
#   "./example-output/one-audio/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/one-audio/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "006653ec2bc14776672c7b41122ea2388d893a4b7314d317ac1a23fd5b25fc6b",
#   "./example-output/one-audio-one-video/output/g3cFdmlkZW8.m3u8" =>
#     "8377780091f8c5d3b7dd4ec6e3160f29c7d41f245ff544c2b2652475d3f93833",
#   "./example-output/one-audio-one-video/output/index.m3u8" =>
#     "4e8ed22cd75655a0325f8db8ce911ffe6950f8d1318f7c9df4bd678ab4e69ba0",
#   "./example-output/one-audio-one-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/one-audio-one-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "d6aaf72aa070c88b7e85d322a589f743c5ffa9e8f1e870f27bde6d0456384ada",
#   "./example-output/one-audio-one-video/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "2db19dba85eae695082b75ae528455db163abda2b0634da4c1dd0cc211119c21",
#   "./example-output/one-video/output/g3cFdmlkZW8.m3u8" =>
#     "a03b3caab7e92232dced4baa8f659808f520f37768084070505ed1090536d914",
#   "./example-output/one-video/output/index.m3u8" =>
#     "e43fef97f7cc8755273b413a70dce4554d1827afe7df072f12b3524860c26e16",
#   "./example-output/one-video/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/one-video/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "40c1f6e975e51374cc102551aa8c4467d4761e9d20ca95fc690487291c925a39",
#   "./example-output/one-video/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "dd35d7b6d03b73ed65aafaf3b47549de20f4a0685be001e294293a33ffbbfc26",
#   "./example-output/only-audio/output/g3cFdmlkZW8.m3u8" =>
#     "d2bc6a7eef32e6b1fa706440e064f703939a1ed9688ebaee3fc3681a1bc05487",
#   "./example-output/only-audio/output/index.m3u8" =>
#     "9a607e4d331a3cef4dde45528b5cacc7ce1473b5effe8f891469815d6bca11d8",
#   "./example-output/only-audio/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/only-audio/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "dd2b6090cbe068f073f5d44ff9827ce90160dfd372a6493e4dea644728ab0e39",
#   "./example-output/only-audio/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "592bbefca206d20e8b89b4537423aa63737b1ac7a0ed2bed52d220d917e64ae9",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/g3cFdmlkZW8.m3u8" =>
#     "e1987ae4a8be930d07803a0d3ed17739b8a0f2a07e0f41650487a8ca109c83a5",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/index.m3u8" =>
#     "bb80020a61bf9c5f7ceadb5ffe50a50671103912dc8c9203fefdd6590265daa6",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "3afa5b4ca0af2de302b0220499a9fd04884324ce56dafa5acb8682f4453fd963",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "75af39ed17b82808f748547045f90da02bcea973e7190dfba71d386b563a7e3f",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "7e9b91614e9b278e9766626332c0e6e91ed13e83f3873350c80ed7a1889eaa81",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_segment_3_g3cFdmlkZW8.m4s" =>
#     "03a244c5b17a987e2b885be65f2fbf0a71720237b7becad983c1d7a17ef17bf8",
#   "./example-output/peer-disconnected-during-recording-and-then-comeback/output/muxed_segment_4_g3cFdmlkZW8.m4s" =>
#     "9ff82d8ab5ba826d114abc5499ae742fe016fe0e5c1b1523db2197fdd9613be7",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/g3cFdmlkZW8.m3u8" =>
#     "8e4cc381cb136c595b25f3aa482aed4cd7dce38d6cf6cfff13be9de4615c10d8",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/index.m3u8" =>
#     "56781159758ae11f903a5aab679b35a64b7d66184d74ba1b64db98ae8b0294a2",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "dc30a84b5139baa7ab9913d108de90d98a925e4e19f67be6b511cacbc678f313",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "e516541b919e8f4977d5bed9d51b6e8e33a4874afe111c9b57d86edc73461fb5",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "ccbe2bec043dbdb90653b1ae4630ac5b7385cb49eed176abfeaad5f56b5b259d",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_segment_3_g3cFdmlkZW8.m4s" =>
#     "f6d965bc98b77b96bfc5ca30e4a370169a67e9356f51d46f3cffea7b1fb72a1b",
#   "./example-output/peer-removes-their-track-during-recording-but-stays-in-the-room/output/muxed_segment_4_g3cFdmlkZW8.m4s" =>
#     "be979e9ba25b72420f7170b671c84eb3a54e4f316b5619a8b0e5ad16d549ceab",
#   "./example-output/peers-before-recording-started/output/g3cFdmlkZW8.m3u8" =>
#     "97fd7ccab36e5b782cb6d3c7eb968e1a9c8ef7c8c206c767af0e4df684f454e3",
#   "./example-output/peers-before-recording-started/output/index.m3u8" =>
#     "d54a370176afdd4345aab18c87632c4ab2d2a76b2e80cda8d7cea60cf1bf470b",
#   "./example-output/peers-before-recording-started/output/muxed_header_g3cFdmlkZW8_part_0.mp4" =>
#     "03754c5fa6ec8c364e7b76ec4fb531c9098fff055fa59622b2561ffade9c1c8d",
#   "./example-output/peers-before-recording-started/output/muxed_segment_0_g3cFdmlkZW8.m4s" =>
#     "9284175d1de5b076513f9091e5a405e5e3ae62e226a2d7f7e3f142cbc0397e84",
#   "./example-output/peers-before-recording-started/output/muxed_segment_1_g3cFdmlkZW8.m4s" =>
#     "484cabb4bba45de90c922e56a89b135280bf3395f95ab43d2e745250fcc69401",
#   "./example-output/peers-before-recording-started/output/muxed_segment_2_g3cFdmlkZW8.m4s" =>
#     "1aa0961190977d1dbf69fd2063a756593e832f1ee0ba7e9a4bd1d0fbcc9da626"
# }

# Enum.each(output_hashes, fn {file_path, file_hash} ->
#   if Map.fetch!(reference_hashes, file_path) != file_hash do
#     IO.inspect("Difference of hash in file #{file_path}")
#     System.stop(1)
#   end
# end)
