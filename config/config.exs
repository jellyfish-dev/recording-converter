import Config

config :recording_converter, terminator: RecordingConverter.Terminator

import_config "#{config_env()}.exs"
