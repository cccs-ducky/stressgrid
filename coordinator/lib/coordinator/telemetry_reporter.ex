defmodule Stressgrid.Coordinator.TelemetryReporter do
  use GenServer

  alias Stressgrid.Coordinator.Scheduler
  alias Stressgrid.Coordinator.TelemetryStore

  @update_interval 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    :erlang.system_flag(:scheduler_wall_time, true)

    send(self(), :update_gauges)

    {:ok, %{wall_times: nil}}
  end

  @impl true
  def handle_info(:update_gauges, state) do
    new_state = if Scheduler.run_active?() do
      report_process_count()
      report_memory_usage()

      report_cpu_usage(state)
    else
      state
    end

    schedule_update()

    {:noreply, new_state}
  end

  defp report_process_count do
    TelemetryStore.gauge(:coordinator_process_count, :erlang.system_info(:process_count))
  end

  defp report_memory_usage do
    total_bytes = Keyword.get(:erlang.memory(), :total, 0)

    TelemetryStore.gauge(:coordinator_memory_used_bytes, total_bytes)
  end

  defp report_cpu_usage(%{wall_times: prev_wall_times} = state) do
    next_wall_times =
      :erlang.statistics(:scheduler_wall_time)
      |> Enum.sort()
      |> Enum.take(:erlang.system_info(:schedulers))

    cpu_utilization =
      if prev_wall_times != nil do
        {da, dt} =
          Enum.zip(prev_wall_times, next_wall_times)
          |> Enum.reduce({0, 0}, fn {{_, a0, t0}, {_, a1, t1}}, {da, dt} ->
            {da + (a1 - a0), dt + (t1 - t0)}
          end)

        if dt > 0, do: da / dt, else: 0
      else
        0
      end

    TelemetryStore.gauge(:coordinator_cpu_percent, round(cpu_utilization * 100))

    %{state | wall_times: next_wall_times}
  end

  defp schedule_update do
    Process.send_after(self(), :update_gauges, @update_interval)
  end
end
