defmodule Stressgrid.Generator.Application do
  @moduledoc false

  alias Stressgrid.Generator.{Connection, Cohort, TelemetryStore}

  use Application

  require Logger

  def start(_type, _args) do
    TelemetryStore.init()

    device_counter = :atomics.new(1, signed: false)
    :persistent_term.put(:sg_device_counter, device_counter)

    telemetry_modules = Application.get_env(:generator, :telemetry_modules, [])

    Enum.each(telemetry_modules, fn module ->
      if Code.ensure_loaded?(module) do
        try do
          module.attach_handlers()
        rescue
          error ->
             Logger.error("Failed to attach telemetry handlers for #{inspect(module)}: #{inspect(error)}")
        end
      end
    end)

    id = Application.get_env(:generator, :generator_id)

    {host, port} =
      case Application.get_env(:generator, :coordinator_url)
           |> URI.parse() do
        %URI{scheme: "ws", host: host, port: port} ->
          {host, port}
      end

    children =
      [
        Cohort.Supervisor,
        {Task.Supervisor, name: Stressgrid.Generator.TaskSupervisor},
        {Connection, id: id, host: host, port: port},
        # children used in generator scripts
        {Registry, keys: :unique, name: PhoenixClient.SocketRegistry},
        TelemetryReporter,
        PhoenixClient.ChannelSupervisor,
        {Finch,
          name: Stressgrid.Generator.Finch,
          pools: %{
            :default => [
              size: 40,
              count: System.schedulers_online(),
              conn_max_idle_time: 60_000,
              conn_opts: [
                transport_opts: [
                  nodelay: true,
                  keepalive: true
                ]
              ]
            ]
          }}
      ] ++ Application.get_env(:stressgrid, :supervisor_children, [])

    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 5,
      name: Stressgrid.Generator.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end
end
