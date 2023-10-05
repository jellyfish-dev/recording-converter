defmodule Mix.Tasks.Lltest do
  @shortdoc "Run LL-HLS stress test"
  @moduledoc """
  # Name

  `mix lltest` - #{@shortdoc}

  # Synopsis

  ```
  mix lltest [--url <url>] [--clients <count>] [--time <seconds>]
             [--spawn-interval <milliseconds>] [--out-path <path>]
             [--jellyfish-address <address>] [--jellyfish-token <token>] [--secure]
  ```

  # Description

  Mix task for running stress-tests on a Jellyfish serving LL-HLS.

  This tool primarily tests the load handling capability and performance
  of the media server. The test simulates multiple clients requesting LL-HLS
  content streams concurrently over a specified duration.

  It saves a CSV file with test results after the full duration of the test has passed,
  which means that if the test is interrupted e.g. using Ctrl-C, the results will NOT be saved.

  # Available options

  * `--url <url>` - URL of the master HLS manifest. This can be inferred from Jellyfish, see below
  * `--clients <count>` - Number of client connections to simulate. Defaults to 500
  * `--time <seconds>` - Duration of the test. Defaults to 300 seconds
  * `--spawn-interval <milliseconds>` - Interval at which to spawn new clients. Defaults to 200 milliseconds
  * `--out-path <path>` - Path to store the CSV with test results. Defaults to "results.csv"

  If `--url <url>` is not passed, the tool will attempt to infer the URL by communicating with Jellyfish.
  This uses the following options:

  * `--jellyfish-address <address>` - Address (structured `<host>:<port>`) of Jellyfish. Defaults to "localhost:5002"
  * `--jellyfish-token <token>` - Jellyfish token. Defaults to "development"
  * `--secure` - By default, the tool will try to communicate with Jellyfish using HTTP.
  If this option is passed, it will use HTTPS instead

  # Example command

  `mix lltest --jellyfish-address my-jellyfish.org:443 --jellyfish-token my-token --secure --clients 2000 --time 600`
  """

  use Mix.Task
  alias Jellygrinder.Coordinator

  @impl true
  def run(argv) do
    Application.ensure_all_started(:jellygrinder)

    {opts, _argv, _errors} =
      OptionParser.parse(argv,
        strict: [
          jellyfish_address: :string,
          jellyfish_token: :string,
          secure: :boolean,
          url: :string,
          clients: :integer,
          time: :integer,
          spawn_interval: :integer,
          out_path: :string
        ]
      )

    client_config =
      Enum.reduce(opts, Keyword.new(), fn {key, value}, config ->
        case key do
          :jellyfish_address -> Keyword.put(config, :server_address, value)
          :jellyfish_token -> Keyword.put(config, :server_api_token, value)
          :secure -> Keyword.put(config, :secure?, value)
          _other -> config
        end
      end)

    coordinator_config =
      opts
      |> Keyword.put(:client_config, client_config)
      |> then(&struct(Coordinator.Config, &1))

    Coordinator.run_test(coordinator_config)
  end
end
