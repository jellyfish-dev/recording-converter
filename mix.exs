defmodule RecordingConverter.Mixfile do
  use Mix.Project

  @version "0.1.0"
  @github_url "https://github.com/jellyfish-dev/recording-converter"

  def project do
    [
      app: :recording_converter,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),

      # hex
      description: "Job that converts Jellyfish recordings to other format",
      package: package(),

      # docs
      name: "Recording Converter",
      source_url: @github_url,
      docs: docs(),

      # test coverage
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "test.cluster": :test,
        "test.cluster.ci": :test
      ]
    ]
  end

  def application do
    [
      mod: {RecordingConverter.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:membrane_core, "~> 1.0"},
      {:membrane_aws_plugin, github: "jellyfish-dev/membrane_aws_plugin"},
      {:membrane_stream_plugin, "~> 0.4.0"},
      {:membrane_rtp_plugin, "~> 0.27.0"},
      {:membrane_rtp_opus_plugin, "~> 0.9.0"},
      {:membrane_rtp_h264_plugin, "~> 0.19.0"},
      {:membrane_h264_format, "~> 0.6.1"},
      {:membrane_h26x_plugin, "~> 0.10.0"},
      {:membrane_aac_plugin, "~> 0.18.0"},
      {:membrane_aac_fdk_plugin, "~> 0.18.5"},
      {:membrane_opus_plugin, "~> 0.20.0"},
      {:membrane_http_adaptive_stream_plugin, "~> 0.18.3"},
      {:jason, "~> 1.0"},
      {:membrane_video_compositor_plugin,
       github: "membraneframework/membrane_video_compositor_plugin"},

      # aws deps
      {:ex_aws, "~> 2.1"},
      {:ex_aws_s3, "~> 2.0"},
      {:sweet_xml, "~> 0.6"},
      {:hackney, "~> 1.20"},

      # Test deps
      {:mox, "~> 1.0", only: [:test, :ci]},
      {:excoveralls, "~> 0.15.0", only: :test, runtime: false},

      # Dialyzer and credo
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end

  defp package do
    [
      maintainers: ["Membrane Team"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @github_url,
        "Membrane Framework Homepage" => "https://membrane.stream"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "LICENSE"],
      formatters: ["html"],
      source_ref: "v#{@version}",
      nest_modules_by_prefix: [RecordingConverter]
    ]
  end
end
