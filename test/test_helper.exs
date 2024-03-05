Mox.defmock(ExAws.Request.HttpMock, for: ExAws.Request.HttpClient)
Mox.defmock(RecordingConverter.TerminatorMock, for: RecordingConverter.Terminator)
ExUnit.start(capture_log: true)
