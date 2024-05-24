defmodule RecordingConverter.FilterH264 do
  @moduledoc false

  use Membrane.Filter

  require Logger

  alias Membrane.Buffer

  def_input_pad :input, accepted_format: Membrane.H264

  def_output_pad :output, accepted_format: Membrane.H264

  @impl true
  def handle_init(_ctx, _options) do
    {[], %{}}
  end

  @impl true
  def handle_buffer(_pad, %Buffer{} = buffer, _ctx, state) do
    type = buffer.metadata.h264.type

    cond do
      type in [:sps, :pps] ->
        {[], Map.put(state, type, buffer)}

      is_map_key(state, :sps) and is_map_key(state, :pps) ->
        buffers = [state.sps, state.pps, buffer]

        {[buffer: {:output, buffers}], %{}}

      map_size(state) > 0 ->
        raise "Stream lacks sps or pps which will lead to decoder deadlock"

      true ->
        {[buffer: {:output, buffer}], state}
    end
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    buffers = [Map.get(state, :sps), Map.get(state, :pps)] |> Enum.reject(&is_nil/1)

    {[buffer: {:output, buffers}, end_of_stream: :output], state}
  end
end
