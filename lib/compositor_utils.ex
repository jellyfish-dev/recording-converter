defmodule RecordingConverter.Compositor do
  @moduledoc false

  @shader_id "shader_1"
  @output_width 1280
  @output_height 720
  @shader_path "./lib/example_shader.wgsl"

  @spec scene(any()) :: map()
  def scene(children) do
    %{
      type: :shader,
      shader_id: @shader_id,
      resolution: %{
        width: @output_width,
        height: @output_height
      },
      children: [
        %{
          id: "tiles_0",
          type: :tiles,
          width: @output_width,
          height: @output_height,
          background_color_rgba: "#000088FF",
          transition: %{
            duration_ms: 300
          },
          margin: 10,
          children: children
        }
      ]
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
end
