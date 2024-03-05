defmodule RecordingConverter.Pipeline do
  use Membrane.Pipeline

  alias Membrane.AWS.S3.Source
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}
  alias Membrane.Time
  alias RecordingConverter.Compositor

  @segment_duration 3
  @output_width 1280
  @output_height 720
  @video_output_id "video_output_1"
  @audio_output_id "audio_output_1"

  @impl true
  def handle_init(_opts, _args) do
    report =
      RecordingConverter.bucket_name()
      |> ExAws.S3.download_file(s3_file_path("report.json"), :memory)
      |> ExAws.stream!()
      |> Enum.join("")

    report = Jason.decode!(report)

    output_directory = RecordingConverter.output_directory()

    main_spec = [
      generate_output_video_branch(output_directory)
    ]

    spec =
      report
      |> Map.fetch!("tracks")
      |> Enum.map(fn {key, value} -> Map.put(value, :id, key) end)
      |> Enum.map(&create_branch(&1))

    {[spec: main_spec ++ spec], %{}}
  end

  @impl true
  def handle_child_notification(
        {msg_type, Pad.ref(_pad_type, _pad_id), _ctx},
        :video_compositor,
        _membrane_ctx,
        state
      )
      when msg_type == :output_registered or msg_type == :input_registered do
    state = %{state | registered_compositor_streams: state.registered_compositor_streams + 1}

    if state.registered_compositor_streams == 4 do
      # send start when all inputs are connected
      {[notify_child: {:video_compositor, :start_composing}], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_child_notification(
        {:lc_request_response, req, %Req.Response{status: response_code, body: response_body},
         _lc_ctx},
        _child,
        _membrane_ctx,
        state
      ) do
    if response_code != 200 do
      raise """
      Request failed.
      Request: `#{inspect(req)}.
      Response code: #{response_code}.
      Response body: #{inspect(response_body)}.
      """
    end

    {[], state}
  end

  @impl true
  def handle_child_notification(:end_of_stream, :hls_sink_bin, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_child_notification(_notification, _other_child, _ctx, state) do
    {[], state}
  end

  defp generate_output_video_branch(output_directory) do
    child(:video_compositor, %Membrane.LiveCompositor{
      framerate: {30, 1},
      composing_strategy: :ahead_of_time,
      init_request: []
    })
    |> via_out(Pad.ref(:video_output, @video_output_id),
      options: [
        encoder_preset: :ultrafast,
        width: @output_width,
        height: @output_height,
        initial:
          scene([
            %{type: :input_stream, input_id: "video_input_0", id: "child_0"}
          ])
      ]
    )
    |> child({:parser, track.id}, %Membrane.H264.Parser{
      generate_best_effort_timestamps: %{framerate: {0, 1}},
      output_alignment: :nalu
    })
    |> via_in(Pad.ref(:input, :video),
      options: [
        encoding: :H264,
        segment_duration: Time.seconds(@segment_duration)
        # segment_duration: state.hls_config.segment_duration,
        # partial_segment_duration: state.hls_config.partial_segment_duration
      ]
    )
    |> child(:hls_sink_bin, %SinkBin{
      hls_mode: :muxed_av,
      storage: %Storages.FileStorage{directory: output_directory},
      manifest_module: Membrane.HTTPAdaptiveStream.HLS
    })
  end

  defp generate_output_audio_branch() do
    get_child(:video_compositor)
    |> via_out(Pad.ref(:audio_output, @audio_output_id),
      options: [
        channels: :stereo,
        initial: %{
          inputs: [
            %{input_id: "audio_input_0", volume: 0.2}
          ]
        }
      ]
    )
    |> child(:opus_output_parser, Membrane.Opus.Parser)
    |> child(:opus_decoder, Membrane.Opus.Decoder)
    |> child(:aac_encoder, Membrane.AAC.FDK.Encoder)
    |> child(:aac_parser, %Membrane.AAC.Parser{out_encapsulation: :none})
    |> via_in(Pad.ref(:input, :audio),
      options: [
        encoding: :AAC,
        segment_duration: Time.seconds(@segment_duration)
        # partial_segment_duration: state.hls_config.partial_segment_duration
      ]
    )
    |> get_child(:hls_sink_bin)
  end

  defp create_branch(%{"encoding" => "H264"} = track) do
    child({:aws_s3, track.id}, %Source{
      bucket: RecordingConverter.bucket_name(),
      path: s3_file_path("/#{track.id}")
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.H264.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child(:mp4_input_parser, %Membrane.H264.Parser{
      output_alignment: :nalu,
      output_stream_structure: :annexb,
      generate_best_effort_timestamps: %{framerate: {0, 1}}
    })
    |> via_in(Pad.ref(:video_input, "video_input_0"),
      options: [
        offset: Membrane.Time.seconds(5),
        required: true
      ]
    )
    |> get_child(:video_compositor)
  end

  defp create_branch(%{"encoding" => "OPUS"} = track) do
    child({:aws_s3, track.id}, %Source{
      bucket: RecordingConverter.bucket_name(),
      path: s3_file_path("/#{track.id}")
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.Opus.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child(:audio_parser, %Membrane.Opus.Parser{
      generate_best_effort_timestamps?: true
    })
    |> via_in(Pad.ref(:audio_input, "audio_input_0"),
      options: [
        offset: Membrane.Time.seconds(5),
        required: true
      ]
    )
    |> get_child(:video_compositor)
  end

  defp create_branch(track),
    do:
      raise(
        "RecordingConverter support only tracks encoded in OPUS or H264. Received track #{inspect(track)} "
      )

  defp s3_file_path(file) do
    Application.fetch_env!(:recording_converter, :input_dir_path) <> file
  end
end
