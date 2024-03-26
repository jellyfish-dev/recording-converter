defmodule RecordingConverter.Terminator do
  @moduledoc false

  @behaviour __MODULE__

  @callback terminate(status_code :: non_neg_integer()) :: :ok

  @spec terminate(number()) :: :ok
  def terminate(status_code) do
    System.stop(status_code)
  end
end
