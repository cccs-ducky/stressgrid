defmodule PhoenixClient.TelemetryReporter do
  use GenServer

  alias Stressgrid.Generator.Connection
  alias Stressgrid.Generator.TelemetryStore

  @update_interval 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    send(self(), :update_gauges)

    {:ok, %{}}
  end

  @impl true
  def handle_info(:update_gauges, state) do
    if Connection.run_active?() do
      report_connection_count()
      report_process_count()
      report_memory_usage()
    end

    schedule_update()

    {:noreply, state}
  end

  defp report_connection_count do
    count =
      Registry.select(PhoenixClient.SocketRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
      |> Enum.reduce(0, fn pid, acc ->
        if Process.alive?(pid) and PhoenixClient.Socket.connected?(pid), do: acc + 1, else: acc
      end)

    # report connections only if was non-zero value was reported at least once
    if count > 0 or TelemetryStore.has_gauge?(:phoenix_client_connections) do
      TelemetryStore.gauge(:phoenix_client_connections, count)
    end
  end

  defp generator_id, do: Application.get_env(:generator, :generator_id)

  defp report_process_count do
    TelemetryStore.gauge(:"generator_#{generator_id()}_process_count", :erlang.system_info(:process_count))
  end

  defp report_memory_usage do
    total_bytes = Keyword.get(:erlang.memory(), :total, 0)

    TelemetryStore.gauge(:"generator_#{generator_id()}_memory_used_bytes", total_bytes)
  end

  defp schedule_update do
    Process.send_after(self(), :update_gauges, @update_interval)
  end
end
