defmodule RecordingConverter.FilterH264 do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.Buffer

  def_input_pad :input, accepted_format: _accepted_format

  def_output_pad :output, accepted_format: _accepted_format

  @impl true
  def handle_init(_ctx, _options) do
    {[], []}
  end

  @impl true
  def handle_buffer(_pad, %Buffer{} = buffer, _ctx, state) do
    IO.inspect(buffer, label: :BUFFER)

    size = Enum.count(state)

    cond do
      buffer.metadata.h264.type in [:sps, :pps] ->
        {[], [buffer | state]}

      size == 3 ->
        buffers = Enum.take(state, 2) ++ [buffer]

        {Enum.flat_map(buffers, &[buffer: {:output, &1}]), []}

      size == 2 ->
        buffers = state ++ [buffer]
        {Enum.flat_map(buffers, &[buffer: {:output, &1}]), []}

      true ->
        {[buffer: {:output, buffer}], state}
    end
  end
end
