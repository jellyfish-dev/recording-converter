defmodule RecordingConverter.RTCPSynchronizer do
  @moduledoc false

  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.RTCP.SenderReportPacket
  alias Membrane.RTCPEvent

  @sec_to_ns 10 ** 9

  def_input_pad :input, accepted_format: Membrane.H264

  def_output_pad :output, accepted_format: Membrane.H264

  def_options clock_rate: [
                spec: pos_integer()
              ]

  @impl true
  def handle_init(_ctx, %{clock_rate: clock_rate}) do
    {[], %{clock_rate: clock_rate, queue: :queue.new(), first_sender_info: nil, offset: 0}}
  end

  @impl true
  def handle_event(
        _pad,
        %RTCPEvent{rtcp: %SenderReportPacket{sender_info: sender_info}},
        _ctx,
        %{first_sender_info: nil, queue: queue} = state
      ) do
    queue = :queue.in({sender_info.rtp_timestamp, 0}, queue)
    {[], %{state | first_sender_info: sender_info, queue: queue}}
  end

  @impl true
  def handle_event(
        _pad,
        %RTCPEvent{rtcp: %SenderReportPacket{sender_info: sender_info}},
        _ctx,
        %{clock_rate: clock_rate, queue: queue} = state
      ) do
    offset = timestamp(sender_info, clock_rate) - timestamp(state.first_sender_info, clock_rate)
    queue = :queue.in({sender_info.rtp_timestamp, offset}, queue)

    {[], %{state | queue: queue}}
  end

  @impl true
  def handle_event(pad, event, context, state) do
    super(pad, event, context, state)
  end

  @impl true
  def handle_buffer(
        _pad,
        %Buffer{} = buffer,
        _ctx,
        %{queue: queue, offset: offset} = state
      ) do
    {offset, queue} =
      if :queue.is_empty(queue),
        do: {offset, queue},
        else: maybe_update_offset(queue, buffer.metadata.rtp.timestamp, offset)

    buffer = Map.update!(buffer, :pts, &(&1 + offset))
    {[buffer: {:output, buffer}], %{state | queue: queue, offset: offset}}
  end

  defp maybe_update_offset(queue, timestamp, offset) do
    {{:value, {next_offset_timestamp, next_offset}}, updated_queue} = :queue.out(queue)
    if next_offset_timestamp < timestamp, do: {next_offset, updated_queue}, else: {offset, queue}
  end

  defp timestamp(%{rtp_timestamp: timestamp, wallclock_timestamp: wallclock}, clock_rate) do
    trunc(wallclock - timestamp / clock_rate * @sec_to_ns)
  end
end
