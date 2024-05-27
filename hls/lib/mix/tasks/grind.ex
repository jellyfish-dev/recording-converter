defmodule Mix.Tasks.Grind do
  @shortdoc "Run HLS stress test on Fishjam"
  @moduledoc """
  # Name

  `mix grind` - #{@shortdoc}

  # Synopsis

  ```
  mix grind [--ll-hls] [--url <url>] [--clients <count>] [--time <seconds>]
            [--spawn-interval <milliseconds>] [--out-path <path>]
            [--fishjam-address <address>] [--fishjam-token <token>] [--secure]
  ```

  # Description

  Mix task for running stress-tests on a Fishjam serving HLS/LL-HLS.

  This tool primarily tests the load handling capability and performance
  of the media server. The test simulates multiple clients requesting HLS
  content streams concurrently over a specified duration.

  It saves a CSV file with test results after the full duration of the test has passed,
  which means that if the test is interrupted e.g. using Ctrl-C, the results will NOT be saved.

  # Available options

  * `--ll-hls` - By default, the tool will use a client compatible with regular HLS.
  If this option is passed, it will use a LL-HLS client instead
  * `--url <url>` - URL of the master HLS manifest. This can be inferred from Fishjam, see below
  * `--clients <count>` - Number of client connections to simulate. Defaults to 500
  * `--time <seconds>` - Duration of the test. Defaults to 300 seconds
  * `--spawn-interval <milliseconds>` - Interval at which to spawn new clients. Defaults to 200 milliseconds
  * `--out-path <path>` - Path to store the CSV with test results. Defaults to "results.csv"

  If `--url <url>` is not passed, the tool will attempt to infer the URL by communicating with Fishjam.
  This uses the following options:

  * `--fishjam-address <address>` - Address (structured `<host>:<port>`) of Fishjam. Defaults to "localhost:5002"
  * `--fishjam-token <token>` - Fishjam token. Defaults to "development"
  * `--secure` - By default, the tool will try to communicate with Fishjam using HTTP.
  If this option is passed, it will use HTTPS instead

  # Notes

  This tool opens a separate TCP connection for every simulated client.
  Users should ensure that both the system running Fishjam and the one running this tool
  are prepared to handle this many connections. This may necessitate:

  * increasing the open port limit, e.g. using `ulimit -n 65536`
  * increasing the number of ports the Erlang VM can use, e.g. by setting the environment variable
  `ELIXIR_ERL_OPTIONS="+Q 65536"`

  # Example command

  `mix grind --fishjam-address my-fishjam.org:443 --fishjam-token my-token --secure --clients 2000 --time 600`
  """

  use Mix.Task
  alias Jellygrinder.Coordinator

  @impl true
  def run(argv) do
    Application.ensure_all_started(:jellygrinder)

    {opts, _argv, _errors} =
      OptionParser.parse(argv,
        strict: [
          fishjam_address: :string,
          fishjam_token: :string,
          secure: :boolean,
          url: :string,
          clients: :integer,
          time: :integer,
          spawn_interval: :integer,
          out_path: :string,
          ll_hls: :boolean
        ]
      )

    client_config =
      Enum.reduce(opts, Keyword.new(), fn {key, value}, config ->
        case key do
          :fishjam_address -> Keyword.put(config, :server_address, value)
          :fishjam_token -> Keyword.put(config, :server_api_token, value)
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
