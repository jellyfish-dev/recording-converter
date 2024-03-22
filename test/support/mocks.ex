Mox.defmock(RecordingConverter.TerminatorMock, for: RecordingConverter.Terminator)
Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)

Application.put_env(:recording_converter, :terminator, RecordingConverter.TerminatorMock)
Application.put_env(:ex_aws, :http_client, ExAws.Request.HttpMock)
