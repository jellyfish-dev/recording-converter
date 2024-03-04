import Config

config :recording_converter,
  bucket_name: "bucket",
  input_dir_path: "test_path/"
  output_dir_path: "output/"

config :ex_aws,
  access_key_id: "dummy",
  secret_access_key: "dummy"
