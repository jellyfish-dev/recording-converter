import Config

config :recording_converter,
  bucket_name: "bucket",
  report_path: "test_path/report.json",
  output_dir_path: "output/",
  compositor_path: System.get_env("COMPOSITOR_PATH")

config :ex_aws,
  access_key_id: "dummy",
  secret_access_key: "dummy"
