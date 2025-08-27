defmodule TelemetryReporter do
  use GenServer

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
    report_connection_count()

    schedule_update()

    {:noreply, state}
  end

  defp report_connection_count do
    count =
      Registry.select(PhoenixClient.SocketRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
      |> Enum.reduce(0, fn pid, acc ->
        if Process.alive?(pid) and PhoenixClient.Socket.connected?(pid), do: acc + 1, else: acc
      end)

    :telemetry.execute([:phoenix_client, :connections, :total], %{count: count}, %{})
  end

  defp schedule_update do
    Process.send_after(self(), :update_gauges, @update_interval)
  end
end
