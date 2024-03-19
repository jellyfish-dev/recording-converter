Mox.defmock(RecordingConverter.TerminatorMock, for: RecordingConverter.Terminator)
Application.put_env(:recording_converter, :terminator, RecordingConverter.TerminatorMock)

Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)
Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)

ExUnit.start(capture_log: true)
