import Config

if config_env() != :test do
  config :recording_converter,
    bucket_name: System.fetch_env!("BUCKET_NAME"),
    input_dir_path: System.fetch_env!("DIRECTORY_PATH"),
    output_dir_path: System.fetch_env!("OUTPUT_DIRECTORY_PATH"),
    compositor_path: System.get_env("COMPOSITOR_PATH")

  access_key_id = System.get_env("AWS_S3_ACCESS_KEY_ID")
  secret_access_key = System.get_env("AWS_S3_SECRET_ACCESS_KEY")
  region = System.get_env("AWS_S3_REGION")

  unless is_nil(access_key_id) or is_nil(secret_access_key) do
    config :ex_aws,
      secret_access_key: secret_access_key,
      access_key_id: access_key_id,
      region: region
  end
end
