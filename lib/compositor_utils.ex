defmodule RecordingConverter.Compositor do
  @moduledoc false

  @shader_id "shader_1"
  @output_width 1280
  @output_height 720
  @shader_path "./lib/example_shader.wgsl"
  @video_output_id "video_output_1"
  @audio_output_id "audio_output_1"

  @spec scene(any()) :: map()
  def scene(children) do
    %{
      id: "tiles_0",
      type: :tiles,
      width: @output_width,
      height: @output_height,
      background_color_rgba: "#000088FF",
      # transition: %{
      #   duration_ms: 300
      # },
      # margin: 10,
      children: children
    }
  end

  def register_shader_request_body() do
    %{
      type: :register,
      entity_type: :shader,
      shader_id: @shader_id,
      source: File.read!(@shader_path)
    }
  end

  def audio_output_id(), do: @audio_output_id
  def video_output_id(), do: @video_output_id

  @spec generate_output_update(String.t(), list(), number()) :: tuple()
  def generate_output_update("video", video_tracks, timestamp) when is_list(video_tracks) do
    {
      :lc_request,
      %{
        type: :update_output,
        output_id: @video_output_id,
        video:
          video_tracks
          |> Enum.map(&%{type: :input_stream, input_id: &1.id})
          |> scene(),
        schedule_time_ms: from_ns_to_ms(timestamp)
      }
    }
  end

  def generate_output_update("audio", audio_tracks, timestamp) when is_list(audio_tracks) do
    {
      :lc_request,
      %{
        type: :update_output,
        output_id: @audio_output_id,
        audio: %{
          inputs: Enum.map(audio_tracks, &%{input_id: &1.id})
        },
        schedule_time_ms: from_ns_to_ms(timestamp)
      }
    }
  end

  def schedule_unregister_video_output(schedule_time_ns),
    do: {
      :lc_request,
      %{
        type: :unregister,
        entity_type: :output_stream,
        output_id: @video_output_id,
        schedule_time_ms: from_ns_to_ms(schedule_time_ns)
      }
    }

  def schedule_unregister_audio_output(schedule_time_ns),
    do: {
      :lc_request,
      %{
        type: :unregister,
        entity_type: :output_stream,
        output_id: @audio_output_id,
        schedule_time_ms: from_ns_to_ms(schedule_time_ns)
      }
    }

  defp from_ns_to_ms(timestamp_ns),
    do: timestamp_ns |> Membrane.Time.nanoseconds() |> Membrane.Time.as_milliseconds(:round)
end
