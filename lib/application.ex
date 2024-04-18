defmodule RecordingConverter.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    children = [RecordingConverter]

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
