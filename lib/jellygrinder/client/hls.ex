defmodule Jellygrinder.Client.HLS do
  @moduledoc false

  @behaviour Jellygrinder.Client

  use GenServer, restart: :temporary
  use Jellygrinder.Client

  alias Jellygrinder.Client.Helpers.{ConnectionManager}

  @max_single_manifest_request_retries 3

  # in ms
  @backoff 1000

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    master_manifest_uri = opts.uri

    {:ok, conn_manager} = ConnectionManager.start_link(master_manifest_uri)

    state = %{
      conn_manager: conn_manager,
      name: opts.name,
      base_path: Path.dirname(master_manifest_uri.path),
      track_manifest_name: nil,
      last_segment: nil,
      target_duration: nil
    }

    {:ok, state, {:continue, {:get_master_manifest, master_manifest_uri.path}}}
  end

  @impl true
  def handle_continue({:get_master_manifest, path}, state) do
    case request(path, "master_playlist", state) do
      {:ok, master_manifest} ->
        send(self(), :get_new_segment)
        track_manifest_name = get_track_manifest_name(master_manifest)

        path = Path.join(state.base_path, track_manifest_name)
        {:ok, track_manifest} = request(path, "media playlist", state)

        target_duration = get_target_duration(track_manifest)

        state = %{
          state
          | track_manifest_name: track_manifest_name,
            target_duration: target_duration
        }

        {:noreply, state}

      {:error, _response} ->
        {:stop, :missing_master_manifest, state}
    end
  end

  @impl true
  def handle_info(:get_new_segment, state) do
    path = Path.join(state.base_path, state.track_manifest_name)

    case request(path, "media playlist", state) do
      {:ok, track_manifest} ->
        last_segment = get_last_segment(track_manifest)

        if state.last_segment != last_segment do
          state.base_path
          |> Path.join(last_segment)
          |> request("media segment", state, @max_single_manifest_request_retries)
        end

        Process.send_after(self(), :get_new_segment, state.target_duration * 1000)

        {:noreply, %{state | last_segment: last_segment}}

      {:error, _response} ->
        Process.send_after(self(), :get_new_segment, @backoff)

        {:noreply, state}
    end
  end

  defp get_last_segment(track_manifest) do
    track_manifest
    |> String.split("\n", trim: true)
    |> List.last()
  end

  defp get_target_duration(track_manifest) do
    {target_duration, _rest} =
      Regex.run(~r/#EXT-X-TARGETDURATION:(.*)/, track_manifest, capture: :all_but_first)
      |> hd()
      |> Integer.parse()

    target_duration
  end
end
