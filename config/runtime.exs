import Config

config :recording_converter,
  compositor_path: System.get_env("COMPOSITOR_PATH"),
  image_url: System.get_env("IMAGE_URL", "https://cdn-icons-png.flaticon.com/512/149/149071.png")

if config_env() != :test do
  config :recording_converter,
    start_recording_converter?: true,
    bucket_name: System.fetch_env!("BUCKET_NAME"),
    report_path: System.fetch_env!("REPORT_PATH"),
    output_dir_path: System.fetch_env!("OUTPUT_DIRECTORY_PATH")

  access_key_id = System.get_env("AWS_S3_ACCESS_KEY_ID")
  secret_access_key = System.get_env("AWS_S3_SECRET_ACCESS_KEY")
  region = System.get_env("AWS_S3_REGION")

  unless is_nil(region) do
    config :ex_aws,
      region: region
  end

  case {access_key_id, secret_access_key} do
    {access_key_id, secret_access_key}
    when not is_nil(access_key_id) and not is_nil(secret_access_key) ->
      config :ex_aws,
        secret_access_key: secret_access_key,
        access_key_id: access_key_id,
        region: region

    {nil, nil} ->
      nil

    _other ->
      Logger.warning("""
      Only one of the two envs AWS_S3_ACCESS_KEY_ID and AWS_S3_SECRET_ACCESS_KEY is set.
      In that case they are ignored.
      """)
  end
end
