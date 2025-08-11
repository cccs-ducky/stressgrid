defmodule Stressgrid.Coordinator.StatsdReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{ReportWriter, StatsdReportWriter}

  @behaviour ReportWriter

  require Logger

  defstruct []

  def init(_opts) do
    %StatsdReportWriter{}
  end

  def start(writer) do
    writer
  end

  def write(id, _clock, %StatsdReportWriter{} = writer, hists, scalars) do
    tags = [run: id]

    hists
    |> Enum.each(fn {key, hist} ->
      if :hdr_histogram.get_total_count(hist) != 0 do
        count = :hdr_histogram.get_total_count(hist)
        mean = :hdr_histogram.mean(hist)
        min = :hdr_histogram.min(hist)
        p50 = :hdr_histogram.percentile(hist, 50.0)
        p75 = :hdr_histogram.percentile(hist, 75.0)
        p95 = :hdr_histogram.percentile(hist, 95.0)
        p99 = :hdr_histogram.percentile(hist, 99.0)
        max = :hdr_histogram.max(hist)

        metric_name = key |> normalize_metric_name()

        Statsd.gauge("#{metric_name}.mean", mean, tags)
        Statsd.gauge("#{metric_name}.min", min, tags)
        Statsd.gauge("#{metric_name}.p50", p50, tags)
        Statsd.gauge("#{metric_name}.p75", p75, tags)
        Statsd.gauge("#{metric_name}.p95", p95, tags)
        Statsd.gauge("#{metric_name}.p99", p99, tags)
        Statsd.gauge("#{metric_name}.max", max, tags)

        Statsd.counter("#{metric_name}.sample_count", count, tags)
      end
    end)

    scalars
    |> Enum.each(fn {key, value} ->
      metric_name = key |> normalize_metric_name()
      Statsd.gauge(metric_name, value, tags)
    end)

    writer
  rescue
    error ->
      Logger.error("StatsD write error: #{inspect(error)}")

      writer
  end

  def finish(result_info, _id, %StatsdReportWriter{}) do
    result_info
  end

  defp normalize_metric_name(metric_name) do
    metric_name
    |> Atom.to_string()
    |> String.replace("_", ".")
  end
end
