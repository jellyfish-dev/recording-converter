import Config

config :recording_converter, terminator: RecordingConverter.Terminator

config :logger,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :ex_aws,
  normalize_path: false

import_config "#{config_env()}.exs"
