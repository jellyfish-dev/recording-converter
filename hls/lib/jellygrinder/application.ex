defmodule Jellygrinder.Application do
  @moduledoc false

  use Application
  alias Jellygrinder.{ClientSupervisor, Coordinator}

  @impl true
  def start(_mode, _opts) do
    children = [
      ClientSupervisor,
      Coordinator
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
