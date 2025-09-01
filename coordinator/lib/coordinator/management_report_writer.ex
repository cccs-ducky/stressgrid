defmodule Stressgrid.Coordinator.ManagementReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{Management, ReportWriter, ManagementReportWriter}

  @behaviour ReportWriter

  @max_history_size 60

  defstruct stats_history: %{}

  def init(_) do
    :ok = Management.notify_all(%{"stats" => %{}})

    nil
  end

  def start(nil) do
    %ManagementReportWriter{}
  end

  def write(_, _, %ManagementReportWriter{stats_history: stats_history} = writer, hists, scalars) do
    stats =
      hists
      |> Enum.filter(fn {_, hist} ->
        :hdr_histogram.get_total_count(hist) != 0
      end)
      |> Enum.map(fn {key, hist} ->
        {key, :hdr_histogram.mean(hist)}
      end)
      |> Enum.concat(scalars)
      |> Map.new()

    missing_keys = Map.keys(stats_history) -- Map.keys(stats)
    report_missing_keys = Application.get_env(:coordinator, :report_missing_keys, true)

    stats_history =
      stats
      |> Enum.map(fn {key, value} ->
        values =
          case Map.get(stats_history, key) do
            nil ->
              [value]

            values ->
              Enum.take([value | values], @max_history_size)
          end

        {key, values}
      end)
      |> then(fn current_stats ->
        if report_missing_keys do
          Enum.concat(
            current_stats,
            Enum.map(missing_keys, fn missing_key ->
              [previous_value | _] = values = Map.get(stats_history, missing_key)
              values = Enum.take([previous_value | values], @max_history_size)

              {missing_key, values}
            end)
          )
        else
          current_stats
        end
      end)
      |> Map.new()

    :ok = Management.notify_all(%{"stats" => stats_history})

    %{writer | stats_history: stats_history}
  end

  def finish(result_info, _, _) do
    :ok = Management.notify_all(%{"stats" => %{}})

    result_info
  end
end
