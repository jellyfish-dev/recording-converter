defmodule RecordingConverter.FilterH264 do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input, accepted_format: Membrane.H264

  def_output_pad :output, accepted_format: Membrane.H264

  @impl true
  def handle_init(_ctx, _options) do
    {[], []}
  end

  @impl true
  def handle_buffer(_pad, %Buffer{} = buffer, _ctx, state) do
    size = Enum.count(state)

    cond do
      buffer.metadata.h264.type in [:sps, :pps] ->
        {[], [buffer | state]}

      size > 0 ->
        find_type = fn type ->
          Enum.find(state, fn buff -> buff.metadata.h264.type == type end)
        end

        sps_buffer = find_type.(:sps)
        pps_buffer = find_type.(:pps)

        buffers = [sps_buffer, pps_buffer, buffer]

        {buffers_to_actions(buffers), []}

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
