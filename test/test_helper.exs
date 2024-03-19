Application.put_env(:recording_converter, :terminator, RecordingConverter.TerminatorMock)
Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)
ExUnit.start(capture_log: true)
