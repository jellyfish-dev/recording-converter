defmodule RecordingConverter.Compositor do
  @moduledoc false

  alias Membrane.LiveCompositor.Request
  alias RecordingConverter.ReportParser

  @text_margin 10
  @letter_width 12
  @output_width 1280
  @output_height 720
  @screenshare_ratio 0.8
  @video_output_id "video_output_1"
  @audio_output_id "audio_output_1"

  @avatar_threshold_ns 1_000_000_000

  @spec avatar_threshold_ns() :: non_neg_integer()
  def avatar_threshold_ns() do
    @avatar_threshold_ns
  end

  @spec server_setup(binary) :: :start_locally | {:start_locally, String.t()}
  def server_setup(compositor_path) do
    compositor_path = compositor_path

    if is_nil(compositor_path) do
      :start_locally
    else
      {:start_locally, compositor_path}
    end
  end

  @spec scene(list()) :: map()
  def scene(children) do
    %{
      id: "tiles_0",
      type: :tiles,
      width: @output_width,
      height: @output_height,
      background_color_rgba: "#00000000",
      children: children
    }
  end

  @spec audio_output_id() :: String.t()
  def audio_output_id(), do: @audio_output_id

  @spec video_output_id() :: String.t()
  def video_output_id(), do: @video_output_id

  @spec generate_output_update(map(), number(), map()) :: [struct()]
  def generate_output_update(tracks, timestamp, camera_tracks_offset),
    do: [
      generate_video_output_update(tracks, timestamp, camera_tracks_offset),
      generate_audio_output_update(tracks, timestamp)
    ]

  @spec schedule_unregister_video_output(number()) :: Request.UnregisterOutput.t() | struct()
  def schedule_unregister_video_output(schedule_time_ns),
    do: %Request.UnregisterOutput{
      output_id: @video_output_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec schedule_unregister_audio_output(number()) :: Request.UnregisterOutput.t() | struct()
  def schedule_unregister_audio_output(schedule_time_ns),
    do: %Request.UnregisterOutput{
      output_id: @audio_output_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec schedule_unregister_input(number(), binary()) :: Request.UnregisterInput.t() | struct()
  def schedule_unregister_input(schedule_time_ns, input_id),
    do: %Request.UnregisterInput{
      input_id: input_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec register_image_action(String.t()) :: Request.RegisterImage.t() | struct()
  def register_image_action(image_url) do
    %Request.RegisterImage{
      asset_type: "png",
      image_id: "avatar_png",
      url: image_url
    }
  end

  defp generate_video_output_update(
         %{"video" => video_tracks, "audio" => audio_tracks},
         timestamp,
         camera_tracks_offset
       )
       when is_list(video_tracks) do
    {camera_tracks, screenshare_tracks} =
      Enum.split_with(video_tracks, &(get_in(&1, ["metadata", "type"]) != "screensharing"))

    camera_tracks_origin = Enum.map(camera_tracks, fn track -> track["origin"] end)

    avatar_tracks =
      Enum.filter(
        audio_tracks,
        &should_have_avatar?(&1, timestamp, camera_tracks_origin, camera_tracks_offset)
      )

    camera_tracks_config =
      Enum.map(camera_tracks, &video_input_source_view/1) ++
        Enum.map(avatar_tracks, &avatar_view/1)

    screenshare_tracks_config = Enum.map(screenshare_tracks, &video_input_source_view/1)

    scene =
      if screenshare_tracks_config != [],
        do: scene_with_screenshare(camera_tracks_config, screenshare_tracks_config),
        else: scene(camera_tracks_config)

    %Request.UpdateVideoOutput{
      output_id: @video_output_id,
      schedule_time: Membrane.Time.nanoseconds(timestamp),
      root: scene
    }
  end

  defp generate_audio_output_update(%{"audio" => audio_tracks}, timestamp)
       when is_list(audio_tracks) do
    %Request.UpdateAudioOutput{
      output_id: @audio_output_id,
      inputs: Enum.map(audio_tracks, &%{input_id: &1.id}),
      schedule_time: Membrane.Time.nanoseconds(timestamp)
    }
  end

  defp scene_with_screenshare(camera_children, screenshare_children) do
    %{
      type: :view,
      width: @output_width,
      height: @output_height,
      direction: :row,
      children: [
        %{
          type: :tiles,
          width: @output_width * @screenshare_ratio,
          children: screenshare_children
        },
        %{type: :tiles, children: camera_children}
      ]
    }
  end

  defp should_have_avatar?(
         %{"origin" => origin} = track,
         timestamp,
         camera_tracks_origin,
         camera_tracks_offset
       ) do
    origin not in camera_tracks_origin and
      longer_than_treshold?(track, timestamp) and
      not has_video_in_threshold?(origin, camera_tracks_offset, timestamp)
  end

  defp longer_than_treshold?(%{"offset" => offset} = track, timestamp) do
    ReportParser.calculate_track_end(track, offset) - timestamp > @avatar_threshold_ns
  end

  defp has_video_in_threshold?(origin, camera_tracks_offset, timestamp) do
    threshold = timestamp + @avatar_threshold_ns

    next_video_offset =
      camera_tracks_offset
      |> Map.get(origin, [])
      |> Enum.find(threshold, &(&1 > timestamp))

    next_video_offset < threshold
  end

  defp video_input_source_view(track) do
    %{
      type: :view,
      children:
        [
          # TODO: fix after compositor update
          # unnecessary rescaler
          %{
            type: :rescaler,
            mode: "fit",
            child: %{
              type: :input_stream,
              input_id: track.id
            }
          }
        ] ++ text_view(track["metadata"])
    }
  end

  defp avatar_view(track) do
    %{
      type: :view,
      children:
        [
          # TODO: fix after compositor update
          # unnecessary rescaler
          %{
            type: :rescaler,
            mode: "fit",
            child: %{
              type: :image,
              image_id: "avatar_png"
            }
          }
        ] ++ text_view(track["metadata"])
    }
  end

  defp text_view(%{"displayName" => label}) do
    letter_width = if contains_emoji?(label), do: @letter_width * 2, else: @letter_width
    label_width = String.length(label) * letter_width + @text_margin

    [
      %{
        type: :view,
        bottom: 20,
        right: 20,
        width: label_width,
        height: 20,
        background_color_rgba: "#000000FF",
        children: [
          %{
            type: :text,
            text: label,
            align: "center",
            width: label_width,
            font_size: 20.0
          }
        ]
      }
    ]
  end

  defp text_view(_metadata), do: []

  defp contains_emoji?(str) do
    # Unicode range for the emoji
    pattern = ~r/[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{1F1E0}-\x{1F1FF}]/u

    Regex.match?(pattern, str)
  end
end
