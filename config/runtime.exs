import Config

if config_env() != :test do
  config :recording_converter,
    bucket_name: System.fetch_env!("BUCKET_NAME"),
    input_dir_path: System.fetch_env!("DIRECTORY_PATH"),
    output_dir_path: System.fetch_env!("OUTPUT_DIRECTORY_PATH")
end
