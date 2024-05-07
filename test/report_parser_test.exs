defmodule RecordingConverter.ReportParserTest do
  use ExUnit.Case

  alias Membrane.LiveCompositor.Request.UpdateVideoOutput
  alias RecordingConverter.ReportParser

  @fixtures "test/fixtures/report_parser/"

  tests = [
    %{report: "short_audio.json", avatars: 0},
    %{report: "long_audio.json", avatars: 1},
    %{report: "audio_video_in_threshold.json", avatars: 0},
    %{report: "audio_video_not_in_threshold.json", avatars: 1},
    %{report: "audio_multiple_video.json", avatars: 0},
    %{report: "audio_video.json", avatars: 2}
  ]

  for test <- tests do
    test "recording with report #{test.report} has #{test.avatars} scenes with avatars" do
      avatar_scenes =
        @fixtures
        |> Path.join(unquote(test.report))
        |> get_tracks()
        |> ReportParser.get_all_track_actions()
        |> get_scenes_with_avatars()

      assert length(avatar_scenes) == unquote(test.avatars)
    end
  end

  defp get_tracks(path) do
    path
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("tracks")
    |> Enum.map(fn {key, value} -> Map.put(value, :id, key) end)
  end

  defp get_scenes_with_avatars(actions) do
    Enum.filter(actions, fn
      %UpdateVideoOutput{root: %{children: children}} -> has_avatar?(children)
      _action -> false
    end)
  end

  defp has_avatar?(children) do
    Enum.any?(children, fn
      %{children: [%{child: %{type: :image}}]} -> true
      _child -> false
    end)
  end
end
