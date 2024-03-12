defmodule RecordingConverter.Pipeline do
  @moduledoc false
  use Membrane.Pipeline

  require Logger

  alias Membrane.AWS.S3.Source
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}
  alias Membrane.Time
  alias RecordingConverter.Compositor

  @segment_duration 3
  @output_width 1280
  @output_height 720
  @output_streams_number 2

  @delta_timestamp_milliseconds 100

  @impl true
  def handle_init(_opts, _args) do
    output_directory = RecordingConverter.output_directory()

    main_spec = [
      generate_sink_bin(output_directory),
      generate_output_audio_branch(),
      generate_output_video_branch()
    ]

    {[spec: main_spec], %{}}
  end

  @impl true
  def handle_setup(_ctx, _state) do
    report =
      RecordingConverter.bucket_name()
      |> ExAws.S3.download_file(s3_file_path("report.json"), :memory)
      |> ExAws.stream!()
      |> Enum.join("")

    report = Jason.decode!(report)

    tracks =
      report
      |> Map.fetch!("tracks")
      |> Enum.map(fn {key, value} -> Map.put(value, :id, key) end)

    tracks_spec = Enum.map(tracks, &create_branch(&1))

    sorted_tracks =
      tracks
      |> Enum.flat_map(fn track ->
        [
          {:start, track, track["offset"]},
          {:end, track, track["offset"] + calculate_track_duration(track)}
        ]
      end)
      |> Enum.sort_by(fn {_atom, _track, timestamp} -> timestamp end)

    update_scene_notifications =
      sorted_tracks
      |> Enum.map_reduce(%{"audio" => [], "video" => []}, fn
        {:start, %{"type" => type} = track, timestamp}, acc ->
          acc = Map.update!(acc, type, &[track | &1])
          {Compositor.generate_output_update(type, acc[type], timestamp), acc}

        {:end, %{"type" => type} = track, timestamp}, acc ->
          acc = Map.update!(acc, type, fn tracks -> Enum.reject(tracks, &(&1 == track)) end)

          {Compositor.generate_output_update(type, acc[type], timestamp), acc}
      end)
      |> then(fn {actions, _acc} -> actions end)

    {audio_tracks, video_tracks} =
      Enum.split_with(sorted_tracks, fn {_atom, track, _timestamp} ->
        track["type"] == "audio"
      end)

    {_atom, audio_track, _timestamp} = Enum.at(audio_tracks, -1)
    {_atom, video_track, _timestamp} = Enum.at(video_tracks, -1)

    unregister_actions =
      [
        audio_track
        |> calculate_track_duration()
        |> Compositor.schedule_unregister_audio_output(),
        video_track |> calculate_track_duration() |> Compositor.schedule_unregister_video_output()
      ]

    actions =
      (update_scene_notifications ++ unregister_actions)
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
      storage: %Storages.FileStorage{directory: output_directory},
      manifest_module: Membrane.HTTPAdaptiveStream.HLS
    })
  end

  defp generate_output_video_branch() do
    child(:video_compositor, %Membrane.LiveCompositor{
      framerate: {30, 1},
      composing_strategy: :ahead_of_time
    })
    |> via_out(Pad.ref(:video_output, Compositor.video_output_id()),
      options: [
        encoder_preset: :ultrafast,
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

  defp generate_output_audio_branch() do
    get_child(:video_compositor)
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

  defp create_branch(track),
    do:
      raise(
        "RecordingConverter support only tracks encoded in OPUS or H264. Received track #{inspect(track)} "
      )

  defp s3_file_path(file) do
    Application.fetch_env!(:recording_converter, :input_dir_path) <> file
  end

  defp notify_compositor(notification) do
    {:notify_child, {:video_compositor, notification}}
  end

  defp calculate_track_duration(track) do
    clock_rate_ms = div(track["clock_rate"], 1_000)

    difference_in_milliseconds =
      div(track["end_timestamp"] - track["start_timestamp"], clock_rate_ms)

    (difference_in_milliseconds - @delta_timestamp_milliseconds)
    |> Membrane.Time.milliseconds()
    |> Membrane.Time.as_nanoseconds(:round)
  end
end
