defmodule RecordingConverter.Pipeline do
  use Membrane.Pipeline

  alias Membrane.AWS.S3.Source
  alias Membrane.HTTPAdaptiveStream.{SinkBin, Storages}
  alias Membrane.Time

  @impl true
  def handle_init(_opts, _args) do
    report =
      bucket_name()
      |> ExAws.S3.download_file(s3_file_path("report.json"), :memory)
      |> ExAws.stream!()
      |> Enum.join("")

    report = Jason.decode!(report)

    File.mkdir("tmp")

    main_spec = [
      # FIXME: Compositor doesn't compile
      # child(:video_compositor, %Membrane.LiveCompositor{
      #   framerate: {30, 1},
      #   server_setup: server_setup,
      #   composing_strategy: :ahead_of_time
      # })
      child(:hls_sink_bin, %SinkBin{
        hls_mode: :muxed_av,
        storage: %Storages.FileStorage{directory: "./tmp"},
        manifest_module: Membrane.HTTPAdaptiveStream.HLS
      })
    ]

    spec =
      report
      |> Map.fetch!("tracks")
      |> Enum.map(fn {key, value} -> Map.put(value, :id, key) end)
      |> Enum.map(&create_branch(&1))

    {[spec: main_spec ++ spec], %{}}
  end

  @impl true
  def handle_child_notification(:end_of_stream, :hls_sink_bin, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_child_notification(_notification, _other_child, _ctx, state) do
    {[], state}
  end

  defp create_branch(%{"encoding" => "H264"} = track) do
    child({:aws_s3, track.id}, %Source{
      bucket: bucket_name(),
      path: s3_file_path("/#{track.id}")
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.H264.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child({:parser, track.id}, %Membrane.H264.Parser{
      generate_best_effort_timestamps: %{framerate: {0, 1}},
      output_alignment: :nalu
    })
    |> via_in(Pad.ref(:input, {:video, track.id}),
      options: [
        encoding: :H264,
        segment_duration: Time.seconds(5)
        # segment_duration: state.hls_config.segment_duration,
        # partial_segment_duration: state.hls_config.partial_segment_duration
      ]
    )
    |> get_child(:hls_sink_bin)
  end

  defp create_branch(%{"encoding" => "OPUS"} = track) do
    child({:aws_s3, track.id}, %Source{
      bucket: bucket_name(),
      path: s3_file_path("/#{track.id}")
    })
    |> child({:deserializer, track.id}, Membrane.Stream.Deserializer)
    |> child({:rtp, track.id}, %Membrane.RTP.DepayloaderBin{
      depayloader: Membrane.RTP.Opus.Depayloader,
      clock_rate: track["clock_rate"]
    })
    |> child(:opus_decoder, Membrane.Opus.Decoder)
    |> child(:aac_encoder, Membrane.AAC.FDK.Encoder)
    |> child(:aac_parser, %Membrane.AAC.Parser{out_encapsulation: :none})
    |> via_in(Pad.ref(:input, {:audio, track.id}),
      options: [
        encoding: :AAC,
        segment_duration: Time.seconds(5)
        # partial_segment_duration: state.hls_config.partial_segment_duration
      ]
    )
    |> get_child(:hls_sink_bin)
  end

  defp create_branch(track),
    do:
      raise(
        "RecordingConverter support only tracks encoded in OPUS or H264. Received track #{inspect(track)} "
      )

  defp bucket_name() do
    Application.fetch_env!(:recording_converter, :bucket_name)
  end

  defp s3_file_path(file) do
    Application.fetch_env!(:recording_converter, :input_dir_path) <> file
  end
end
