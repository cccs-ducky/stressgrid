defmodule Stressgrid.Coordinator.CsvReportWriter do
  @moduledoc false

  alias Stressgrid.Coordinator.{ReportWriter, CsvReportWriter, GeneratorBasics}

  @behaviour ReportWriter

  @management_base "priv/management"
  @results_base "results"

  defstruct table: %{}

  def init() do
    %CsvReportWriter{}
  end

  def write_hists(_, clock, %CsvReportWriter{table: table} = writer, hists) do
    row =
      hists
      |> Enum.filter(fn {_, hist} ->
        :hdr_histogram.get_total_count(hist) != 0
      end)
      |> Enum.map(fn {key, hist} ->
        mean = :hdr_histogram.mean(hist)
        min = :hdr_histogram.min(hist)
        pc1 = :hdr_histogram.percentile(hist, 1.0)
        pc10 = :hdr_histogram.percentile(hist, 10.0)
        pc25 = :hdr_histogram.percentile(hist, 25.0)
        median = :hdr_histogram.median(hist)
        pc75 = :hdr_histogram.percentile(hist, 75.0)
        pc90 = :hdr_histogram.percentile(hist, 90.0)
        pc99 = :hdr_histogram.percentile(hist, 99.0)
        max = :hdr_histogram.max(hist)
        stddev = :hdr_histogram.stddev(hist)

        [
          {key, mean},
          {:"#{key}_min", min},
          {:"#{key}_pc1", pc1},
          {:"#{key}_pc10", pc10},
          {:"#{key}_pc25", pc25},
          {:"#{key}_median", median},
          {:"#{key}_pc75", pc75},
          {:"#{key}_pc90", pc90},
          {:"#{key}_pc99", pc99},
          {:"#{key}_max", max},
          {:"#{key}_stddev", stddev}
        ]
      end)
      |> Enum.concat()
      |> Map.new()
      |> Map.merge(table |> Map.get(clock, %{}))

    %{writer | table: table |> Map.put(clock, row)}
  end

  def write_scalars(_, clock, %CsvReportWriter{table: table} = writer, scalars) do
    row =
      scalars
      |> Map.new()
      |> Map.merge(table |> Map.get(clock, %{}))

    %{writer | table: table |> Map.put(clock, row)}
  end

  def write_basics(
        _,
        clock,
        %CsvReportWriter{table: table} = writer,
        basics
      ) do
    basics_count = Enum.count(basics)

    average_cpu =
      if basics_count === 0 do
        0
      else
        (basics
         |> Enum.map(fn {_, %GeneratorBasics{cpu: cpu}} -> cpu end)
         |> Enum.sum()) / basics_count
      end

    total_network_rx =
      basics
      |> Enum.map(fn {_, %GeneratorBasics{network_rx: network_rx}} -> network_rx end)
      |> Enum.sum()

    total_network_tx =
      basics
      |> Enum.map(fn {_, %GeneratorBasics{network_tx: network_tx}} -> network_tx end)
      |> Enum.sum()

    total_active_device_count =
      basics
      |> Enum.map(fn {_, %GeneratorBasics{active_device_count: active_device_count}} ->
        active_device_count
      end)
      |> Enum.sum()

    row =
      basics
      |> Enum.map(fn {generator,
                      %GeneratorBasics{
                        cpu: cpu,
                        network_rx: network_rx,
                        network_tx: network_tx,
                        active_device_count: active_device_count
                      }} ->
        [
          {:"#{generator}_cpu", cpu},
          {:"#{generator}_network_rx", network_rx},
          {:"#{generator}_network_tx", network_tx},
          {:"#{generator}_active_device_count", active_device_count}
        ]
      end)
      |> Enum.concat()
      |> Map.new()
      |> Map.put(:average_cpu, average_cpu)
      |> Map.put(:total_network_rx, total_network_rx)
      |> Map.put(:total_network_tx, total_network_tx)
      |> Map.put(:total_active_device_count, total_active_device_count)
      |> Map.merge(table |> Map.get(clock, %{}))

    %{writer | table: table |> Map.put(clock, row)}
  end

  def finish(result_info, id, %CsvReportWriter{
        table: table
      }) do
    tmp_directory = Path.join([System.tmp_dir(), id])
    File.mkdir_p!(tmp_directory)

    write_csv(table, Path.join([tmp_directory, "results.csv"]))

    filename = "#{id}.tar.gz"
    directory = Path.join([Application.app_dir(:coordinator), @management_base, @results_base])
    File.mkdir_p!(directory)

    result_info =
      case System.cmd("tar", ["czf", Path.join(directory, filename), "-C", System.tmp_dir(), id]) do
        {_, 0} ->
          result_info |> Map.merge(%{"csv_url" => Path.join([@results_base, filename])})

        _ ->
          result_info
      end

    File.rm_rf!(Path.join([System.tmp_dir(), id]))

    result_info
  end

  defp write_csv(table, file_name) do
    keys =
      table
      |> Enum.reduce([], fn {_, row}, keys ->
        row
        |> Enum.reduce(keys, fn {key, _}, keys -> [key | keys] end)
        |> Enum.uniq()
      end)
      |> Enum.sort()

    keys_string =
      keys
      |> Enum.map(&"#{&1}")
      |> Enum.join(",")

    io_data =
      ["clock,#{keys_string}\r\n"] ++
        (table
         |> Enum.sort_by(fn {clock, _} -> clock end)
         |> Enum.map(fn {clock, row} ->
           values_string =
             keys
             |> Enum.map(fn key ->
               case row |> Map.get(key) do
                 nil ->
                   ""

                 value ->
                   "#{value}"
               end
             end)
             |> Enum.join(",")

           "#{clock},#{values_string}\r\n"
         end)
         |> Enum.to_list())

    File.write!(file_name, io_data)
  end
end
