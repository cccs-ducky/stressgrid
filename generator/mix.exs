defmodule Stressgrid.Generator.MixProject do
  use Mix.Project

  def project do
    maybe_load_custom_deps()

    [
      app: :generator,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(),
      deps: deps()
    ]
  end

  defp scripts_path do
    System.get_env("SCRIPTS_PATH") || "scripts"
  end

  defp maybe_load_custom_deps do
    deps_path = Path.join(scripts_path(), "config/deps.exs")

    deps = if File.exists?(deps_path) do
      {deps, _bindings} = Code.eval_file(deps_path)

      deps
    else
      []
    end

    Process.put(:custom_config, %{
      deps: deps
    })
  end

  defp custom_config(key) do
    Map.get(Process.get(:custom_config, %{}), key)
  end

  defp elixirc_paths(), do: ["lib", scripts_path()]

  def application do
    [
      extra_applications: [:logger] ++ extra_applications(Mix.env()),
      mod: {Stressgrid.Generator.Application, []}
    ]
  end

  defp extra_applications(:dev), do: [:observer, :wx]
  defp extra_applications(_), do: []

  defp deps do
    [
      {:gun, "~> 1.3.0"},
      # contains build fix for otp-26
      {:hdr_histogram,
        git: "https://github.com/HdrHistogram/hdr_histogram_erl.git",
        tag: "39991d346382e0add74fed2e8ec1cd5666061541"},
      {:jason, "~> 1.4"},
      {:bertex, "~> 1.3"},
      {:dialyxir, "~> 1.4", runtime: false}
    ] ++ custom_config(:deps)
  end
end
