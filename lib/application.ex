defmodule RecordingConverter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children =
      if Application.get_env(:recording_converter, :start_recording_converter?) do
        System.trap_signal(:sigterm, fn ->
          Application.fetch_env!(:recording_converter, :terminator).terminate(1)
        end)

        [RecordingConverter]
      else
        []
      end

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [
      strategy: :one_for_one,
      name: RecordingConverter.Supervisor,
      max_restarts: 0
    ]

    Supervisor.start_link(children, opts)
  end
end
