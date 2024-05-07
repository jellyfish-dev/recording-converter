defmodule RecordingConverter.ReportParser do
  @moduledoc false

  alias RecordingConverter.Compositor

  @delta_timestamp_milliseconds 100
  @max_timestamp_value 2 ** 32 - 1

  @type track_action :: {{:start | :end}, map(), non_neg_integer()}

  @spec get_tracks(bucket_name :: binary(), report_path :: binary()) :: list()
  def get_tracks(bucket_name, report_path) do
    bucket_name
    |> get_report(report_path)
    |> Map.fetch!("tracks")
    |> Enum.map(fn {key, value} -> Map.put(value, :id, key) end)
  end

  @spec get_all_track_actions(tracks :: list()) :: list()
  def get_all_track_actions(tracks) do
    tracks_actions = get_track_actions(tracks)
    video_tracks_offset = get_video_tracks_offset(tracks)

    update_scene_notifications =
      create_update_scene_notifications(tracks_actions, video_tracks_offset)

    unregister_output_actions = generate_unregister_output_actions(tracks_actions)

    update_scene_notifications ++ unregister_output_actions
  end

  @spec calculate_track_end(map(), non_neg_integer()) :: non_neg_integer()
  def calculate_track_end(track, offset) do
    clock_rate_ms = div(track["clock_rate"], 1_000)

    end_timestamp = track["end_timestamp"]
    start_timestamp = track["start_timestamp"]

    timestamp_difference =
      if end_timestamp < start_timestamp do
        end_timestamp + @max_timestamp_value - start_timestamp
      else
        end_timestamp - start_timestamp
      end

    difference_in_milliseconds = div(timestamp_difference, clock_rate_ms)

    duration =
      (difference_in_milliseconds - @delta_timestamp_milliseconds)
      |> Membrane.Time.milliseconds()
      |> Membrane.Time.as_nanoseconds(:round)

    offset + duration
  end

  defp get_report(bucket_name, report_path) do
    bucket_name
    |> ExAws.S3.download_file(report_path, :memory)
    |> ExAws.stream!()
    |> Enum.join("")
    |> Jason.decode!()
  end

  defp get_video_tracks_offset(tracks) do
    tracks
    |> Enum.filter(&(&1["type"] == "video"))
    |> Enum.reduce(%{}, fn %{"origin" => origin, "offset" => offset}, acc ->
      Map.update(acc, origin, [offset], &[offset | &1])
    end)
    |> Map.new(fn {origin, offset} -> {origin, Enum.sort(offset)} end)
  end

  defp get_track_actions(tracks) do
    tracks
    |> Enum.flat_map(fn track ->
      offset = track["offset"]

      [
        {:start, track, offset},
        {:end, track, calculate_track_end(track, offset)}
      ]
    end)
    |> Enum.sort_by(fn {_atom, _track, timestamp} -> timestamp end)
  end

  defp create_update_scene_notifications(track_actions, video_tracks_offset) do
    track_actions
    |> Enum.map_reduce(%{"audio" => [], "video" => []}, fn
      {:start, %{"type" => type} = track, timestamp}, acc ->
        acc = Map.update!(acc, type, &[track | &1])
        {Compositor.generate_output_update(acc, timestamp, video_tracks_offset), acc}

      {:end, %{"type" => type} = track, timestamp}, acc ->
        acc = Map.update!(acc, type, fn tracks -> Enum.reject(tracks, &(&1 == track)) end)
        {Compositor.generate_output_update(acc, timestamp, video_tracks_offset), acc}
    end)
    |> then(fn {actions, _acc} -> actions end)
    |> List.flatten()
  end

  defp generate_unregister_output_actions(track_actions) do
    {audio_end_timestamp, video_end_timestamp} = get_audio_and_video_end_timestamp(track_actions)

    case {audio_end_timestamp, video_end_timestamp} do
      {nil, nil} ->
        raise "Don't have any timestamp fatal error"

      {nil, timestamp} ->
        [
          Compositor.schedule_unregister_audio_output(timestamp),
          Compositor.schedule_unregister_video_output(timestamp)
        ]

      {timestamp, nil} ->
        [
          Compositor.schedule_unregister_audio_output(timestamp),
          Compositor.schedule_unregister_video_output(timestamp)
        ]

      {audio_ts, video_ts} ->
        [
          Compositor.schedule_unregister_audio_output(audio_ts),
          Compositor.schedule_unregister_video_output(video_ts)
        ]
    end
  end

  defp get_audio_and_video_end_timestamp(track_actions) do
    {audio_tracks, video_tracks} =
      Enum.split_with(track_actions, fn {_atom, track, _timestamp} ->
        track["type"] == "audio"
      end)

    audio_end_timestamp = calculate_end_timestamp(audio_tracks)
    video_end_timestamp = calculate_end_timestamp(video_tracks)

    {audio_end_timestamp, video_end_timestamp}
  end

  defp calculate_end_timestamp(tracks) do
    if Enum.count(tracks) > 0 do
      {_atom, _video_track, timestamp} = Enum.at(tracks, -1)
      timestamp
    else
      nil
    end
  end
end
