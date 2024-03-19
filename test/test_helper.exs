Mox.defmock(RecordingConverter.TerminatorMock, for: RecordingConverter.Terminator)
Application.put_env(:recording_converter, :terminator, RecordingConverter.TerminatorMock)

Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)

ExUnit.start(capture_log: true)
