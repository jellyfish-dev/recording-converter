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

        {buffers_to_actions(buffers), %{}}

      map_size(state) > 0 ->
        raise "Stream lacks sps or pps which will lead to decoder deadlock"

      true ->
        {[buffer: {:output, buffer}], state}
    end
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {buffers_to_actions(state) ++ [end_of_stream: :output], state}
  end

  defp buffers_to_actions(buffers) do
    Enum.flat_map(buffers, &[buffer: {:output, &1}])
  end
end
