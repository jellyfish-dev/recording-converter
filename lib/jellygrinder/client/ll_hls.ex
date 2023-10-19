defmodule Jellygrinder.Client.LLHLS do
  @moduledoc false

  @behaviour Jellygrinder.Client

  use GenServer, restart: :temporary
  use Jellygrinder.Client

  alias Jellygrinder.Client.Helpers.ConnectionManager

  @max_partial_request_count 12
  @max_single_partial_request_retries 3

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
      latest_partial: nil
    }

    {:ok, state, {:continue, {:get_master_manifest, master_manifest_uri.path}}}
  end

  @impl true
  def handle_continue({:get_master_manifest, path}, state) do
    case request(path, "master playlist", state) do
      {:ok, master_manifest} ->
        send(self(), :get_new_partials)
        track_manifest_name = get_track_manifest_name(master_manifest)

        {:noreply, %{state | track_manifest_name: track_manifest_name}}

      {:error, _response} ->
        {:stop, :missing_master_manifest, state}
    end
  end

  @impl true
  def handle_info(:get_new_partials, state) do
    path = Path.join(state.base_path, state.track_manifest_name)
    query = create_track_manifest_query(state)

    case request(path <> query, "media playlist", state) do
      {:ok, track_manifest} ->
        latest_partial =
          track_manifest
          |> get_new_partials(state.latest_partial)
          |> Stream.each(&request_partial(&1, state))
          |> Stream.take(-1)
          |> Enum.to_list()
          |> List.first(state.latest_partial)

        send(self(), :get_new_partials)

        {:noreply, %{state | latest_partial: latest_partial}}

      {:error, _response} ->
        Process.send_after(self(), :get_new_partials, @backoff)

        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp create_track_manifest_query(%{latest_partial: nil} = _state), do: ""

  defp create_track_manifest_query(%{latest_partial: latest_partial} = _state) do
    [last_msn, last_part] =
      Regex.run(~r/^muxed_segment_(\d+)_\w*_(\d+)_part.m4s$/, latest_partial,
        capture: :all_but_first
      )
      |> Enum.map(&String.to_integer/1)

    # This may not be the correct client behaviour, but it is handled by Jellyfish
    # TODO: rewrite when the client starts handling preload hints
    "?_HLS_msn=#{last_msn}&_HLS_part=#{last_part + 1}"
  end

  defp get_new_partials(track_manifest, latest_partial) do
    track_manifest
    |> trim_manifest(latest_partial)
    |> then(&Regex.scan(~r/^#EXT-X-PART:.*URI="(.*)"/m, &1, capture: :all_but_first))
    |> Enum.take(-@max_partial_request_count)
    |> List.flatten()
  end

  defp request_partial(partial_name, %{base_path: base_path} = state) do
    base_path
    |> Path.join(partial_name)
    |> request("media partial segment", state, @max_single_partial_request_retries)
  end
end
