defmodule Stressgrid.Coordinator.MixProject do
  use Mix.Project

  def project do
    [
      app: :coordinator,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools] ++ extra_applications(Mix.env()),
      mod: {Stressgrid.Coordinator.Application, []}
    ]
  end

  defp extra_applications(:dev), do: [:observer, :wx]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:phoenix, "~> 1.7.21"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:plug_cowboy, "~> 2.7"},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.2.0", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.1.1",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:cowboy, "~> 2.6"},
      {:jason, "~> 1.4"},
      # contains build fix for otp-26
      {:hdr_histogram,
       git: "https://github.com/HdrHistogram/hdr_histogram_erl.git",
       tag: "39991d346382e0add74fed2e8ec1cd5666061541"},
      {:ex_aws_cloudwatch, "~> 2.0"},
      {:httpoison, "~> 1.6"},
      {:dialyxir, "~> 1.4", runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind coordinator", "esbuild coordinator"],
      "assets.deploy": [
        "tailwind coordinator --minify",
        "esbuild coordinator --minify",
        "phx.digest"
      ]
    ]
  end
end
