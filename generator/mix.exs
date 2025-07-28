defmodule Stressgrid.Generator.Mixfile do
  use Mix.Project

  def project do
    [
      app: :generator,
      version: "0.1.0",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Stressgrid.Generator.Application, []}
    ]
  end

  defp deps do
    [
      {:gun, "~> 1.3.0"},
      # contains build fix for otp-26
      {:hdr_histogram,
        git: "https://github.com/HdrHistogram/hdr_histogram_erl.git",
        tag: "39991d346382e0add74fed2e8ec1cd5666061541"},
      {:jason, "~> 1.1"},
      {:bertex, "~> 1.3"},
      {:dialyxir, "~> 1.4", runtime: false}
    ]
  end
end
