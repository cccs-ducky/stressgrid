defmodule Stressgrid.Generator.Application do
  @moduledoc false

  alias Stressgrid.Generator.{Connection, Cohort}

  use Application

  @default_coordinator_url "ws://localhost:9696"

  def start(_type, _args) do
    id =
      System.get_env("GENERATOR_ID", default_generator_id())

    {host, port} =
      case System.get_env("COORDINATOR_URL", @default_coordinator_url)
           |> URI.parse() do
        %URI{scheme: "ws", host: host, port: port} ->
          {host, port}
      end

    children =
      [
        Cohort.Supervisor,
        {Task.Supervisor, name: Stressgrid.Generator.TaskSupervisor},
        {Connection, id: id, host: host, port: port}
      ] ++ Application.get_env(:stressgrid, :supervisor_children, [])

    opts = [
      strategy: :one_for_one,
      max_restarts: 10,
      max_seconds: 5,
      name: Stressgrid.Generator.Supervisor
    ]

    Supervisor.start_link(children, opts)
  end

  defp default_generator_id do
    host = :inet.gethostname() |> elem(1) |> to_string()

    uniq = :rand.uniform(1_000_000_000)

    "#{host}-#{uniq}"
  end
end
