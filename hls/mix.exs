defmodule Jellygrinder.MixProject do
  use Mix.Project

  def project do
    [
      app: :jellygrinder,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jellygrinder.Application, []}
    ]
  end

  defp elixirc_paths(_env), do: ["lib"]

  defp deps do
    [
      {:mint, "~> 1.5"},
      {:castore, "~> 1.0"},
      {:fishjam_server_sdk, "~> 0.6.0"},
      {:dialyxir, ">= 0.0.0", only: :dev, runtime: false},
      {:credo, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp dialyzer() do
    opts = [
      flags: [:error_handling],
      plt_add_apps: [:mix]
    ]

    if System.get_env("CI") == "true" do
      # Store PLTs in cacheable directory for CI
      [plt_local_path: "priv/plts", plt_core_path: "priv/plts"] ++ opts
    else
      opts
    end
  end
end
