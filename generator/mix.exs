defmodule Stressgrid.Generator.MixProject do
  use Mix.Project

  def project do
    maybe_load_custom_mix_ext()

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
    System.get_env("SCRIPTS_PATH") || read_dotenv_scripts_path() || "scripts"
  end

  defp read_dotenv_scripts_path do
    if File.exists?(".env") do
      ".env"
      |> File.read!()
      |> String.split("\n")
      |> Enum.find_value(fn line ->
        case String.split(String.trim(line), "=", parts: 2) do
          ["SCRIPTS_PATH", value] -> String.trim(value)
          _ -> nil
        end
      end)
    end
  end

  defp maybe_load_custom_mix_ext do
    custom_mix_exs = Path.expand(Path.join(scripts_path(), "config/mix.exs"), __DIR__)

    bindings =
      if File.exists?(custom_mix_exs) do
        {_, bindings} = Code.eval_file(custom_mix_exs)

        bindings
      else
        []
      end

    Application.put_env(:stressgrid, :custom_deps, Keyword.get(bindings, :deps, []))

    Application.put_env(
      :stressgrid,
      :supervisor_children,
      Keyword.get(bindings, :supervisor_children, [])
    )
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
      {:dialyxir, "~> 1.4", runtime: false},
      {:dotenv, "~> 3.1"},
      {:telemetry_metrics, "~> 1.1"},
      # deps used in generator scripts
      {:tesla, "~> 1.11"},
      {:finch, "~> 0.20"},
      {:websocket_client, "~> 1.5"}
    ] ++ Application.get_env(:stressgrid, :custom_deps, [])
  end
end
