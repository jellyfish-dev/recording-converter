defmodule Jellygrinder.Client do
  @moduledoc false

  alias Jellygrinder.Client
  alias Jellygrinder.Client.Helpers.ConnectionManager
  alias Jellygrinder.Coordinator

  @type options() :: %{uri: URI.t(), name: String.t()}

  @callback start_link(options()) :: GenServer.on_start()

  @doc false
  defmacro __using__(_opts) do
    quote do
      def request(path, label, state, retries \\ 0) do
        Client.request(path, label, state, retries)
      end

      def get_track_manifest_name(master_manifest) do
        Client.get_track_manifest_name(master_manifest)
      end

      def trim_manifest(manifest, pattern) do
        Client.trim_manifest(manifest, pattern)
      end
    end
  end

  @spec request(String.t(), String.t(), map(), non_neg_integer()) :: {:ok | :error, binary()}
  def request(path, label, state, 0), do: request_and_log(path, label, state)

  def request(path, label, state, retries) do
    case request_and_log(path, label, state) do
      {:ok, _content} = response -> response
      {:error, _reason} -> request(path, label, state, retries - 1)
    end
  end

  @spec get_track_manifest_name(String.t()) :: String.t()
  def get_track_manifest_name(master_manifest) do
    master_manifest
    |> String.split("\n", trim: true)
    |> List.last()
  end

  @doc """
  Trim the manifest, returning everything after `pattern`
  If `pattern == nil` or `pattern` isn't present in manifest, return the entire manifest
  """
  @spec trim_manifest(String.t(), String.t() | nil) :: String.t()
  def trim_manifest(manifest, nil), do: manifest

  def trim_manifest(manifest, pattern) do
    manifest
    |> String.split(pattern, parts: 2)
    |> Enum.at(1, manifest)
  end

  defp request_and_log(path, label, state) do
    timestamp = get_current_timestamp_ms()
    start_time = System.monotonic_time()
    maybe_response = ConnectionManager.get(state.conn_manager, path)
    end_time = System.monotonic_time()

    request_info = %{
      timestamp: timestamp,
      elapsed: System.convert_time_unit(end_time - start_time, :native, :millisecond),
      label: label,
      process_name: state.name,
      path: path
    }

    {result, data} =
      case maybe_response do
        {:ok, response} ->
          success = response.status == 200
          data = Map.get(response, :data, "")

          {%{
             response_code: response.status,
             success: success,
             failure_msg: if(success, do: "", else: data),
             bytes: byte_size(data)
           }, data}

        {:error, reason} ->
          handle_failed_request(reason, state)

          {%{
             response_code: -1,
             success: false,
             failure_msg: inspect(reason),
             bytes: -1
           }, ""}
      end

    GenServer.cast(Coordinator, {:result, Map.merge(request_info, result)})

    {if(result.success, do: :ok, else: :error), data}
  end

  defp get_current_timestamp_ms() do
    {megaseconds, seconds, microseconds} = :os.timestamp()

    megaseconds * 1_000_000_000 + seconds * 1000 + div(microseconds, 1000)
  end

  defp handle_failed_request(%error_struct{reason: :closed}, state)
       when error_struct in [Mint.HTTPError, Mint.TransportError] do
    # Make a single attempt to reconnect whenever a request fails with reason `:closed`
    ConnectionManager.reconnect(state.conn_manager)
  end

  defp handle_failed_request(_other_error, _state), do: nil
end
