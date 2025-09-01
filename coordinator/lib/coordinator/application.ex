defmodule Stressgrid.Coordinator.Application do
  @moduledoc false

  use Application
  require Logger

  alias Stressgrid.Coordinator.{
    GeneratorConnection,
    GeneratorRegistry,
    Reporter,
    Scheduler,
    CsvReportWriter,
    CloudWatchReportWriter,
    StatsdReportWriter,
    Management,
    ManagementReportWriter,
    TelemetryStore,
    TelemetryReporter
  }

  @management_report_writer_interval_ms 1_000

  @impl true
  def start(_type, _args) do
    TelemetryStore.init()
    
    generators_port = Application.get_env(:coordinator, :generators_port)

    report_interval_ms = Application.get_env(:coordinator, :report_interval_seconds) * 1000
    report_writers = Application.get_env(:coordinator, :report_writers, [])

    all_writer_configs = %{
      "csv" => {CsvReportWriter, [], report_interval_ms},
      "cloudwatch" => {CloudWatchReportWriter, [], report_interval_ms},
      "statsd" => {StatsdReportWriter, [], report_interval_ms}
    }

    writer_configs =
      (report_writers
       |> Enum.map(&Map.get(all_writer_configs, &1))
       |> Enum.reject(&is_nil/1)) ++
        [{ManagementReportWriter, [], @management_report_writer_interval_ms}]

    children = [
      Management.registry_spec(),
      Management,
      GeneratorRegistry,
      TelemetryReporter,
      {Statsd,
       [
         prefix: Application.get_env(:coordinator, :telemetry)[:statsd_prefix],
         host: Application.get_env(:coordinator, :telemetry)[:statsd_host],
         metrics: [],
         formatter: :datadog,
         mtu: Application.get_env(:coordinator, :telemetry)[:mtu] || 1432,
         pool_size:
           Application.get_env(:coordinator, :telemetry)[:pool_size] || System.schedulers_online(),
         buffer_flush_ms: Application.get_env(:coordinator, :telemetry)[:buffer_flush_ms] || 1000
       ]},
      {Reporter, writer_configs: writer_configs},
      Scheduler,

      # cowboy deps
      cowboy_sup(:generators_listener, generators_port, generators_dispatch()),

      # phoenix deps
      Stressgrid.CoordinatorWeb.Telemetry,
      {Phoenix.PubSub, name: Stressgrid.Coordinator.PubSub},
      Stressgrid.CoordinatorWeb.Endpoint
    ]

    Logger.info("Listening for generators on port #{generators_port}")

    opts = [strategy: :one_for_one, name: Stressgrid.Coordinator.Supervisor]

    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Stressgrid.CoordinatorWeb.Endpoint.config_change(changed, removed)

    :ok
  end

  defp cowboy_sup(id, port, dispatch) do
    %{
      id: id,
      start: {:cowboy, :start_clear, [id, [port: port], %{env: %{dispatch: dispatch}}]},
      restart: :permanent,
      shutdown: :infinity,
      type: :supervisor
    }
  end

  defp generators_dispatch do
    :cowboy_router.compile([{:_, [{"/", GeneratorConnection, %{}}]}])
  end
end
