defmodule Jellygrinder.ClientSupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Jellygrinder.Client.{HLS, LLHLS}

  @type client :: LLHLS | HLS

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(arg) do
    DynamicSupervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @spec spawn_client(client(), term()) :: DynamicSupervisor.on_start_child()
  def spawn_client(client_module, arg) do
    DynamicSupervisor.start_child(__MODULE__, {client_module, arg})
  end

  @spec terminate() :: :ok
  def terminate() do
    DynamicSupervisor.stop(__MODULE__)
  end

  @impl true
  def init(_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
