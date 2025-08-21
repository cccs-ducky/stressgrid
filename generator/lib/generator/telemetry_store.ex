defmodule Stressgrid.Generator.TelemetryStore do
  @moduledoc """
  High-performance global telemetry store using ETS for scalars and histograms
  that can be shared across different telemetry handlers and connection types.
  Optimized for maximum write throughput.
  """

  @scalars_table :telemetry_scalars
  @hists_table :telemetry_hists

  def init do
    :ets.new(@scalars_table, [
      :named_table,
      :public,
      :set,
      {:write_concurrency, true},
      {:read_concurrency, true},
      {:decentralized_counters, true}
    ])

    :ets.new(@hists_table, [
      :named_table,
      :public,
      :set,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])
  end

  def inc_counter(key, value \\ 1) do
    counter_key = {key, :count}

    :ets.update_counter(@scalars_table, counter_key, value, {counter_key, 0})

    :ok
  catch
    :error, :badarg ->
      :ets.insert(@scalars_table, {{key, :count}, value})

      :ok
  end

  def gauge(key, value) do
    :ets.insert(@scalars_table, {{key, :total}, value})

    :ok
  catch
    :error, :badarg ->
      :ets.insert(@scalars_table, {{key, :total}, value})

      :ok
  end

  def record_hist(key, value) do
    key_us = if Atom.to_string(key) |> String.contains?("_us"), do: key, else: :"#{key}_us"

    case :ets.lookup(@hists_table, key_us) do
      [{^key_us, hist}] ->
        :hdr_histogram.record(hist, value)

      [] ->
        hist = create_hist()

        :hdr_histogram.record(hist, value)

        :ets.insert(@hists_table, {key_us, hist})
    end

    :ok
  end

  def collect do
    current_scalars = :ets.tab2list(@scalars_table) |> Map.new()
    current_hists_list = :ets.tab2list(@hists_table)
    current_hists = current_hists_list |> Map.new()

    :ok =
      current_hists_list
      |> Enum.each(fn {_, hist} ->
        :ok = :hdr_histogram.reset(hist)
      end)

    current_scalars
    |> Enum.each(fn {key, _value} ->
      :ets.insert(@scalars_table, {key, 0})
    end)

    %{
      scalars: current_scalars,
      hists: current_hists
    }
  end

  defp create_hist do
    {:ok, hist} = :hdr_histogram.open(60_000_000, 3)
    hist
  end
end
