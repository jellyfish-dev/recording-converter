import Config

config :recording_converter,
  bucket_name: "bucket",
  input_dir_path: "test_path/",
  output_dir_path: "output/",
  compositor_path: nil,
  terminator: RecordingConverter.TerminatorMock

config :ex_aws,
  access_key_id: "dummy",
  secret_access_key: "dummy"
