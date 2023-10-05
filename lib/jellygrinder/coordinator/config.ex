defmodule Jellygrinder.Coordinator.Config do
  @moduledoc false

  @default_client_config [
    server_address: "localhost:5002",
    server_api_token: "development",
    secure?: false
  ]

  @type t :: %__MODULE__{
          client_config: Jellyfish.Client.connection_options(),
          url: String.t() | nil,
          clients: pos_integer(),
          time: pos_integer(),
          spawn_interval: pos_integer(),
          out_path: Path.t()
        }

  defstruct client_config: @default_client_config,
            url: nil,
            clients: 500,
            time: 300,
            spawn_interval: 200,
            out_path: "results.csv"

  @spec fill_hls_url!(t()) :: t() | no_return()
  def fill_hls_url!(%{url: nil} = config) do
    client_config = Keyword.merge(@default_client_config, config.client_config)
    client = Jellyfish.Client.new(client_config)

    case Jellyfish.Room.get_all(client) do
      {:ok, [room | _rest]} ->
        protocol = if client_config[:secure?], do: "https", else: "http"

        %{
          config
          | url: "#{protocol}://#{client_config[:server_address]}/hls/#{room.id}/index.m3u8"
        }

      {:ok, []} ->
        raise "No rooms present on Jellyfish"

      {:error, reason} ->
        raise "Error communicating with Jellyfish: #{inspect(reason)}"
    end
  end

  def fill_hls_url!(config), do: config
end
