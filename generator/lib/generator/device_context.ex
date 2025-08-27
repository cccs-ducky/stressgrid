defmodule Stressgrid.Generator.DeviceContext do
  @moduledoc false

  alias Stressgrid.Generator.{Device}

  import Bitwise

  defmacro start_timing(key) do
    quote do
      Device.start_timing(Process.get(:device_pid), unquote(key))
    end
  end

  defmacro stop_timing(key) do
    quote do
      Device.stop_timing(Process.get(:device_pid), unquote(key))
    end
  end

  defmacro stop_start_timing(key) do
    quote do
      Device.stop_start_timing(Process.get(:device_pid), unquote(key), unquote(key))
    end
  end

  defmacro stop_start_timing(stop_key, start_key) do
    quote do
      Device.stop_start_timing(Process.get(:device_pid), unquote(stop_key), unquote(start_key))
    end
  end

  defmacro record_timing(key, value) do
    quote do
      Device.record_timing(Process.get(:device_pid), unquote(key), unquote(value))
    end
  end

  defmacro inc_counter(key, value \\ 1) do
    quote do
      Device.inc_counter(Process.get(:device_pid), unquote(key), unquote(value))
    end
  end

  defmacro generator_numeric_id do
    quote do
      Process.get(:generator_numeric_id)
    end
  end

  defmacro generators_count do
    quote do
      :persistent_term.get(:sg_generator_count, 1)
    end
  end

  defmacro device_numeric_id do
    quote do
      Process.get(:device_numeric_id)
    end
  end

  def delay(milliseconds, random_ratio \\ 0)
      when random_ratio >= 0.0 and random_ratio <= 1.0 do
    Process.sleep(trunc(milliseconds * (1.0 + random_ratio * (:rand.uniform() * 2.0 - 1.0))))
  end

  def random_bits(size) when size > 0 do
    shift = rem(size, 8)

    if shift == 0 do
      random_bytes(div(size, 8))
    else
      <<head::size(8), bytes::binary>> = random_bytes(div(size, 8) + 1)
      <<head >>> (8 - shift)::size(8), bytes::binary>>
    end
  end

  def random_bytes(size) when size > 0 do
    :crypto.strong_rand_bytes(size)
  end

  def payload(size) do
    random_bytes(size)
  end

  # convenience methods to make stats macros work in subprocesses
  def set_device_vars(vars) when is_map(vars) do
    if Map.has_key?(vars, :device_id), do: Process.put(:device_id, vars.device_id)
    if Map.has_key?(vars, :device_pid), do: Process.put(:device_pid, vars.device_pid)
    if Map.has_key?(vars, :device_numeric_id), do: Process.put(:device_numeric_id, vars.device_numeric_id)
    if Map.has_key?(vars, :generator_id), do: Process.put(:generator_id, vars.generator_id)
    if Map.has_key?(vars, :generator_numeric_id), do: Process.put(:generator_numeric_id, vars.generator_numeric_id)
  end

  def set_device_vars(vars) when is_list(vars) do
    if Keyword.has_key?(vars, :device_id), do: Process.put(:device_id, Keyword.get(vars, :device_id))
    if Keyword.has_key?(vars, :device_pid), do: Process.put(:device_pid, Keyword.get(vars, :device_pid))
    if Keyword.has_key?(vars, :device_numeric_id), do: Process.put(:device_numeric_id, Keyword.get(vars, :device_numeric_id))
    if Keyword.has_key?(vars, :generator_id), do: Process.put(:generator_id, Keyword.get(vars, :generator_id))
    if Keyword.has_key?(vars, :generator_numeric_id), do: Process.put(:generator_numeric_id, Keyword.get(vars, :generator_numeric_id))
  end
end
