defmodule RecordingConverter.Compositor do
  @moduledoc false

  alias Membrane.LiveCompositor.Request

  @output_width 1280
  @output_height 720
  @video_output_id "video_output_1"
  @audio_output_id "audio_output_1"

  @spec server_setup(binary) :: :start_locally | {:start_locally, String.t()}
  def server_setup(compositor_path) do
    compositor_path = compositor_path

    if is_nil(compositor_path) do
      :start_locally
    else
      {:start_locally, compositor_path}
    end
  end

  @spec scene(any()) :: map()
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

  @spec generate_output_update(map(), number()) :: [tuple()]
  def generate_output_update(tracks, timestamp),
    do: [
      generate_video_output_update(tracks, timestamp),
      generate_audio_output_update(tracks, timestamp)
    ]

  @spec schedule_unregister_video_output(number()) :: Request.t()
  def schedule_unregister_video_output(schedule_time_ns),
    do: %Request.UnregisterOutput{
      output_id: @video_output_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec schedule_unregister_audio_output(number()) :: Request.t()
  def schedule_unregister_audio_output(schedule_time_ns),
    do: %Request.UnregisterOutput{
      output_id: @audio_output_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec schedule_unregister_input(number(), binary()) :: Request.t()
  def schedule_unregister_input(schedule_time_ns, input_id),
    do: %Request.UnregisterInput{
      input_id: input_id,
      schedule_time: Membrane.Time.nanoseconds(schedule_time_ns)
    }

  @spec register_image_action(String.t()) :: Request.t()
  def register_image_action(image_url) do
    %Request.RegisterImage{
      asset_type: :png,
      image_id: "avatar_png",
      url: image_url
    }
  end

  defp generate_video_output_update(
         %{"video" => video_tracks, "audio" => audio_tracks},
         timestamp
       )
       when is_list(video_tracks) do
    video_tracks_id = Enum.map(video_tracks, fn track -> track["origin"] end)
    avatar_tracks = Enum.reject(audio_tracks, fn track -> track["origin"] in video_tracks_id end)

    avatars_config = Enum.map(avatar_tracks, &avatar_view/1)
    video_tracks_config = Enum.map(video_tracks, &video_input_source_view/1)

    %Request.UpdateVideoOutput{
      output_id: @video_output_id,
      schedule_time: Membrane.Time.nanoseconds(timestamp),
      root: scene(video_tracks_config ++ avatars_config)
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

  defp video_input_source_view(track) do
    %{
      type: :view,
      children:
        [
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
    [
      %{
        type: :view,
        bottom: 20,
        right: 20,
        height: 20,
        background_color_rgba: "#000000FF",
        children: [
          %{type: :view},
          %{
            type: :text,
            text: label,
            font_size: 20.0
          },
          %{type: :view}
        ]
      }
    ]
  end

  defp text_view(_metadata), do: []
end
