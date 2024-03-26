defmodule RecordingConverter.ReportParser do
  @moduledoc false

  alias RecordingConverter.Compositor

  @delta_timestamp_milliseconds 100

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

    update_scene_notifications = create_update_scene_notifications(tracks_actions)
    unregister_output_actions = generate_unregister_output_actions(tracks_actions)
    unregister_input_actions = generate_unregister_input_actions(tracks_actions)

    update_scene_notifications ++ unregister_input_actions ++ unregister_output_actions
  end

  defp get_report(bucket_name, report_path) do
    bucket_name
    |> ExAws.S3.download_file(report_path, :memory)
    |> ExAws.stream!()
    |> Enum.join("")
    |> Jason.decode!()
  end

  defp get_track_actions(tracks) do
    tracks
    |> Enum.flat_map(fn track ->
      offset = track["offset"]

      [
        {:start, track, offset},
        {:end, track, offset + calculate_track_duration(track)}
      ]
    end)
    |> Enum.sort_by(fn {_atom, _track, timestamp} -> timestamp end)
  end

  defp create_update_scene_notifications(track_actions) do
    track_actions
    |> Enum.map_reduce(%{"audio" => [], "video" => []}, fn
      {:start, %{"type" => type} = track, timestamp}, acc ->
        acc = Map.update!(acc, type, &[track | &1])
        {Compositor.generate_output_update(type, acc[type], timestamp), acc}

      {:end, %{"type" => type} = track, timestamp}, acc ->
        acc = Map.update!(acc, type, fn tracks -> Enum.reject(tracks, &(&1 == track)) end)
        {Compositor.generate_output_update(type, acc[type], timestamp), acc}
    end)
    |> then(fn {actions, _acc} -> actions end)
  end

  defp generate_unregister_output_actions(track_actions) do
    {audio_end_timestamp, video_end_timestamp} =
      get_audio_and_video_end_timestamp(track_actions)

    [
      Compositor.schedule_unregister_audio_output(audio_end_timestamp),
      Compositor.schedule_unregister_video_output(video_end_timestamp)
    ]
    |> Enum.reject(&is_nil(&1))
  end

  defp generate_unregister_input_actions(track_actions) do
    track_actions
    |> Enum.filter(fn {atom, _track, _offset} -> atom == :end end)
    |> Enum.map(fn {_atom, track, offset} ->
      Compositor.schedule_unregister_input(offset, track.id)
    end)
  end

  defp get_audio_and_video_end_timestamp(track_actions) do
    {audio_tracks, video_tracks} =
      Enum.split_with(track_actions, fn {_atom, track, _timestamp} ->
        track["type"] == "audio"
      end)

    audio_end_timestamp = calculate_end_timestamp(audio_tracks)
    video_end_timestamp = calculate_end_timestamp(video_tracks)

    {audio_end_timestamp || video_end_timestamp, video_end_timestamp || audio_end_timestamp}
  end

  defp calculate_track_duration(track) do
    clock_rate_ms = div(track["clock_rate"], 1_000)

    difference_in_milliseconds =
      div(track["end_timestamp"] - track["start_timestamp"], clock_rate_ms)

    (difference_in_milliseconds - @delta_timestamp_milliseconds)
    |> Membrane.Time.milliseconds()
    |> Membrane.Time.as_nanoseconds(:round)
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
