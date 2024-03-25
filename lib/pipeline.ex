defmodule RecordingConverter.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  require Logger

  alias Membrane.AWS.S3.Source
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}
  alias Membrane.Time
  alias RecordingConverter.{Compositor, ReportParser}

  @segment_duration 3
  @output_width 1280
  @output_height 720
  @output_streams_number 2
  @report_file "report.json"

  @impl true
  def handle_init(_ctx, opts) do
    output_directory = opts.output_directory

    case File.ls(output_directory) do
      {:ok, files} when files != [] ->
        Logger.warning("Warning: Some files #{Enum.join(files, ", ")} were found in output directory. They will be removed.")
        File.rm_rf(output_directory)

      _other ->
        nil
    end

    File.mkdir_p!(output_directory)

    main_spec =
      [
        generate_sink_bin(output_directory),
        generate_output_audio_branch(opts),
        generate_output_video_branch(opts)
      ]
      |> Enum.reject(&is_nil(&1))

    {[spec: main_spec], opts}
  end

  @impl true
  def handle_setup(_ctx, state) do
    report_path = s3_file_path(@report_file, state)

    tracks = ReportParser.get_tracks(state.bucket_name, report_path)

    if Enum.empty?(tracks) do
      raise "RecordingConverter can't do anything with recording without tracks"
    end

    tracks_spec = Enum.map(tracks, &create_branch(&1, state))

    actions =
      tracks
      |> ReportParser.get_all_track_actions()
      |> Enum.map(&notify_compositor/1)

    actions = [{:spec, tracks_spec} | actions]

    {actions,
     %{
       tracks: Enum.count(tracks_spec) + @output_streams_number,
       registered_compositor_streams: 0,
       unregistered_compositor_streams: Enum.count(tracks_spec)
     }}
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

    if state.registered_compositor_streams == state.tracks do
      # send start when all inputs are connected
      {[notify_compositor(:start_composing)], state}
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
  def handle_child_notification(notification, _other_child, _ctx, state) do
    Logger.warning("Unexpected notification: #{inspect(notification)}")
    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(:hls_sink_bin, _pad, _context, state) do
    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(_element, _pad, _context, state) do
    {[], state}
  end

  defp generate_sink_bin(output_directory) do
    child(:hls_sink_bin, %SinkBin{
      hls_mode: :muxed_av,
      target_window_duration: :infinity,
      persist?: true,
      storage: %Storages.FileStorage{directory: output_directory},
      manifest_module: Membrane.HTTPAdaptiveStream.HLS
    })
  end

  defp generate_output_video_branch(_state) do
    get_child(:video_compositor)
    |> via_out(Pad.ref(:video_output, Compositor.video_output_id()),
      options: [
        encoder_preset: :slow,
        width: @output_width,
        height: @output_height,
        initial:
          Compositor.scene([
            %{type: :input_stream, input_id: "video_input_0", id: "child_0"}
          ])
      ]
    )
    |> child(:output_video_parser, %Membrane.H264.Parser{
      generate_best_effort_timestamps: %{framerate: {30, 1}},
      output_alignment: :nalu
    })
    |> via_in(Pad.ref(:input, :video),
      options: [
        encoding: :H264,
        segment_duration: Time.seconds(@segment_duration)
      ]
    )
    |> get_child(:hls_sink_bin)
  end

  defp generate_output_audio_branch(state) do
    child(:video_compositor, %Membrane.LiveCompositor{
      framerate: {30, 1},
      composing_strategy: :ahead_of_time,
      server_setup: Compositor.server_setup(state.compositor_path)
    })
    |> via_out(Pad.ref(:audio_output, Compositor.audio_output_id()),
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
      ]
    )
    |> get_child(:hls_sink_bin)
  end

  defp create_branch(%{"encoding" => "H264"} = track, state) do
    child({:aws_s3, track.id}, %Source{
      bucket: state.bucket_name,
      path: s3_file_path("/#{track.id}", state)
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.H264.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child({:input_parser, track.id}, %Membrane.H264.Parser{
      output_alignment: :nalu,
      output_stream_structure: :annexb,
      generate_best_effort_timestamps: %{framerate: {0, 1}}
    })
    |> via_in(Pad.ref(:video_input, track.id),
      options: [
        offset: Membrane.Time.nanoseconds(track["offset"]),
        required: true
      ]
    )
    |> get_child(:video_compositor)
  end

  defp create_branch(%{"encoding" => "OPUS"} = track, state) do
    child({:aws_s3, track.id}, %Source{
      bucket: state.bucket_name,
      path: s3_file_path("/#{track.id}", state)
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.Opus.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child({:input_parser, track.id}, %Membrane.Opus.Parser{
      generate_best_effort_timestamps?: true
    })
    |> via_in(Pad.ref(:audio_input, track.id),
      options: [
        offset: Membrane.Time.nanoseconds(track["offset"]),
        required: true
      ]
    )
    |> get_child(:video_compositor)
  end

  defp create_branch(track, _state),
    do:
      raise(
        "RecordingConverter support only tracks encoded in OPUS or H264. Received track #{inspect(track)} "
      )

  defp s3_file_path(file, state) do
    Path.join(state.s3_directory, file)
  end

  defp notify_compositor(notification) do
    {:notify_child, {:video_compositor, notification}}
  end
end
