defmodule Stressgrid.Generator.Device do
  @moduledoc false

  alias Stressgrid.Generator.{Device, DeviceContext, Histogram, ScriptDevice}

  require Logger

  defstruct module: nil,
            task_fn: nil,
            task: nil,
            script_error: nil,
            hists: %{},
            scalars: %{},
            last_tss: %{}

  defmacro __using__(opts) do
    device_functions = opts |> Keyword.get(:device_functions, [])
    device_macros = opts |> Keyword.get(:device_macros, [])

    quote do
      alias Stressgrid.Generator.Device

      def device_functions do
        unquote(device_functions)
      end

      def device_macros do
        unquote(device_macros)
      end

      @impl true
      def handle_call(
            {:collect, to_hists},
            _,
            state
          ) do
        {r, state} = state |> Device.do_collect(to_hists)
        {:reply, r, state}
      end

      @impl true
      def handle_call(
            {:start_timing, key},
            _,
            state
          ) do
        {:reply, :ok, state |> Device.do_start_timing(key)}
      end

      @impl true
      def handle_call(
            {:stop_timing, key},
            _,
            state
          ) do
        {:reply, :ok, state |> Device.do_stop_timing(key)}
      end

      @impl true
      def handle_call(
            {:stop_start_timing, stop_key, start_key},
            _,
            state
          ) do
        {:reply, :ok, state |> Device.do_stop_start_timing(stop_key, start_key)}
      end

      @impl true
      def handle_call(
            {:record_timing, key, value},
            _,
            state
          ) do
        {:reply, :ok, state |> Device.record_hist(:"#{key}_us", value)}
      end

      @impl true
      def handle_call(
            {:inc_counter, key, value},
            _,
            state
          ) do
        {:reply, :ok, state |> Device.do_inc_counter(key, value)}
      end

      @impl true
      def handle_info(
            {:init, id, generator_id, generator_numeric_id, address, task_script, task_params},
            state
          ) do
        {:noreply,
         state
         |> Device.do_init(
           __MODULE__,
           id,
           generator_id,
           generator_numeric_id,
           address,
           task_script,
           task_params,
           unquote(device_functions),
           unquote(device_macros)
         )}
      end

      @impl true
      def handle_info(:open, state) do
        {:noreply,
         state
         |> Device.do_open()}
      end

      @impl true
      def handle_info(
            {task_ref, :ok},
            %{device: %Device{task: %Task{ref: task_ref}} = device} = state
          )
          when is_reference(task_ref) do
        {:noreply, state |> Device.do_task_completed()}
      end

      @impl true
      def handle_info(
            {:DOWN, task_ref, :process, task_pid, reason},
            %{
              device:
                %Device{
                  task: %Task{
                    ref: task_ref,
                    pid: task_pid
                  }
                } = device
            } = state
          ) do
        {:noreply, state |> Device.do_task_down(reason)}
      end

      @impl true
      def handle_info({:EXIT, _pid, reason}, state) do
        state =
          case state.device.task do
            nil ->
              state

            task ->
              Task.shutdown(task, :brutal_kill)
              %{state | device: %{state.device | task: nil}}
          end

        {:noreply, state}
      end

      @impl true
      def terminate(reason, state) do
        case state.device.task do
          nil -> :ok
          task -> Task.shutdown(task, :brutal_kill)
        end

        :ok
      end
    end
  end

  @recycle_delay 1_000

  def collect(pid, to_hists) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:collect, to_hists})
    else
      {:ok, nil, false, %{}, %{}}
    end
  end

  def start_timing(pid, key) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:start_timing, key})
    else
      :ok
    end
  end

  def stop_timing(pid, key) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:stop_timing, key})
    else
      :ok
    end
  end

  def stop_start_timing(pid, stop_key, start_key) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:stop_start_timing, stop_key, start_key})
    else
      :ok
    end
  end

  def inc_counter(pid, key, value) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:inc_counter, key, value})
    else
      :ok
    end
  end

  def record_timing(pid, key, value) do
    if Process.alive?(pid) do
      GenServer.call(pid, {:record_timing, key, value})
    else
      :ok
    end
  end

  def init(state, args) do
    Process.flag(:trap_exit, true)

    id = args |> Keyword.fetch!(:id)
    generator_id = args |> Keyword.fetch!(:generator_id)
    generator_numeric_id = args |> Keyword.fetch!(:generator_numeric_id)
    address = args |> Keyword.fetch!(:address)
    task_script = args |> Keyword.fetch!(:script)
    task_params = args |> Keyword.fetch!(:params)

    _ =
      Kernel.send(
        self(),
        {:init, id, generator_id, generator_numeric_id, address, task_script, task_params}
      )

    Map.merge(state, %{
      id: id,
      device: %Device{}
    })
  end

  def do_collect(
        %{
          device:
            %Device{script_error: script_error, hists: from_hists, scalars: scalars, task: task} =
              device
        } = state,
        to_hists
      ) do
    hists = Histogram.add(to_hists, from_hists)

    :ok =
      from_hists
      |> Enum.each(fn {_, hist} ->
        :ok = :hdr_histogram.reset(hist)
      end)

    reset_scalars =
      scalars
      |> Enum.map(fn {key, _} -> {key, 0} end)
      |> Map.new()

    {{:ok, script_error, task != nil, hists, scalars},
     %{state | device: %{device | scalars: reset_scalars}}}
  end

  def do_init(
        %{device: device} = state,
        module,
        id,
        generator_id,
        generator_numeric_id,
        address,
        task_script,
        task_params,
        device_functions,
        device_macros
      ) do
    Logger.debug("Init device #{id}")

    %Macro.Env{functions: functions, macros: macros} = __ENV__

    {protocol, _, _, _} = address

    device_pid = self()

    base_device_functions =
      {DeviceContext,
       [
         delay: 1,
         delay: 2,
         payload: 1,
         random_bits: 1,
         random_bytes: 1
       ]
       |> Enum.sort()}

    base_device_macros =
      {DeviceContext,
       [
         start_timing: 1,
         stop_timing: 1,
         stop_start_timing: 1,
         stop_start_timing: 2,
         record_timing: 2,
         inc_counter: 1,
         inc_counter: 2,
         generator_numeric_id: 0,
         generators_count: 0
       ]
       |> Enum.sort()}

    try do
      processed_script =
        case protocol do
          :script ->
            # replace all defmodule occurrences with defmodule_noop to avoid re-defining modules
            # this is needed to avoid module redefinition errors when the script is reloaded ad-hoc
            # modules are extracted and defined only once in prepare_script/1
            task_script |> String.replace(~r/\bdefmodule\b/, "defmodule_noop")

          _ ->
            task_script
        end

      {task_fn, _} =
        "fn -> #{processed_script} end"
        |> Code.eval_string(
          [
            id: id,
            generator_id: generator_id,
            generator_numeric_id: generator_numeric_id,
            device_pid: device_pid,
            params: task_params
          ],
          %Macro.Env{
            __ENV__
            | module: nil,
              functions: functions ++ [base_device_functions] ++ device_functions,
              macros: macros ++ [base_device_macros] ++ device_macros
          }
        )

      state = %{
        state
        | device: %{
            device
            | module: module,
              task_fn: task_fn
          }
      }

      Kernel.apply(module, :open, [state])
    catch
      :error, error ->
        %{state | device: %{device | script_error: %{error: error, script: task_script}}}
    end
  end

  # pre-evals script modules before running cohorts, it's done only once to ensure no concurrent module definitions done
  def prepare_script(task_script) do
    %Macro.Env{functions: functions, macros: macros} = __ENV__

    base_device_functions =
      {DeviceContext,
       [
         delay: 1,
         delay: 2,
         payload: 1,
         random_bits: 1,
         random_bytes: 1
       ]
       |> Enum.sort()}

    base_device_macros =
      {DeviceContext,
       [
         start_timing: 1,
         stop_timing: 1,
         stop_start_timing: 1,
         stop_start_timing: 2,
         record_timing: 2,
         inc_counter: 1,
         inc_counter: 2,
         generator_numeric_id: 0,
         generators_count: 0
       ]
       |> Enum.sort()}

    if String.contains?(task_script, "defmodule") do
      prepared_script =
        extract_modules(task_script) |> String.replace(~r/\bdefmodule\b/, "defmodulex")

      {task_fn, _} =
        "fn -> #{prepared_script} end"
        |> Code.eval_string(
          [],
          %Macro.Env{
            __ENV__
            | module: nil,
              functions:
                functions ++
                  [base_device_functions] ++ ScriptDevice.device_functions(),
              macros:
                macros ++
                  [base_device_macros] ++ ScriptDevice.device_macros()
          }
        )

      Task.await(
        Task.async(fn ->
          try do
            Code.put_compiler_option(:ignore_module_conflict, true)

            task_fn.()

            Code.put_compiler_option(:ignore_module_conflict, false)

            :ok
          rescue
            error ->
              Logger.error("Error in script module preparation: #{inspect(error)}")

              {:error, "Error in script module preparation: #{inspect(error)}"}
          catch
            :exit, reason ->
              Logger.error("Script module preparation exited with reason: #{inspect(reason)}")

              {:error, "Script module preparation exited with reason: #{inspect(reason)}"}
          end
        end)
      )
    end
  end

  def extract_modules(task_script) do
    case Code.string_to_quoted(task_script) do
      {:ok, ast} ->
        modules = extract_defmodule_nodes(ast)

        modules_code =
          modules
          |> Enum.map(&Macro.to_string/1)
          |> Enum.join("\n\n")

        modules_code

      {:error, error} ->
        {:error, error}
    end
  end

  defp extract_defmodule_nodes(ast) when is_list(ast) do
    ast
    |> Enum.reduce([], fn node, acc ->
      case extract_defmodule_nodes(node) do
        [] -> acc
        modules -> modules ++ acc
      end
    end)
    |> Enum.reverse()
  end

  defp extract_defmodule_nodes({:defmodule, _, _} = node) do
    [node]
  end

  defp extract_defmodule_nodes({_, _, children}) when is_list(children) do
    children
    |> Enum.reduce([], fn child, acc ->
      case extract_defmodule_nodes(child) do
        [] -> acc
        modules -> modules ++ acc
      end
    end)
    |> Enum.reverse()
  end

  defp extract_defmodule_nodes(_), do: []

  def start_task(%{device: %Device{task: nil, task_fn: task_fn} = device} = state) do
    task =
      Task.Supervisor.async_nolink(Stressgrid.Generator.TaskSupervisor, fn ->
        try do
          task_fn.()
        catch
          :exit, :device_terminated ->
            :ok
        end

        :ok
      end)

    %{state | device: %{device | task: task}}
  end

  def do_task_completed(%{device: %Device{task: %Task{ref: task_ref}}} = state) do
    Logger.debug("Script exited normally for device #{state.id}")

    true = Process.demonitor(task_ref, [:flush])

    state |> do_recycle(false)
  end

  def do_task_down(
        state,
        reason
      ) do
    next_state =
      state
      |> do_recycle(true)
      |> do_inc_counter(reason |> task_reason_to_key(), 1)

    %{
      next_state
      | device: %{next_state.device | script_error: %{error: reason}}
    }
  end

  def do_open(%{device: %Device{module: module}} = state) do
    Kernel.apply(module, :open, [state])
  end

  def do_recycle(
        %{device: %Device{module: module, task: task} = device} = state,
        delay
      ) do
    Logger.debug("Recycle device #{state.id}")

    if task != nil do
      Task.shutdown(task, :brutal_kill)
    end

    state = %{state | device: %{device | task: nil, last_tss: %{}}}
    state = Kernel.apply(module, :close, [state])

    if delay do
      _ = Process.send_after(self(), :open, @recycle_delay)
      state
    else
      state |> do_open()
    end
  end

  def recycle(state) do
    state |> do_recycle(true)
  end

  def do_inc_counter(%{device: %Device{scalars: scalars} = device} = state, key, value) do
    %{
      state
      | device: %{
          device
          | scalars:
              scalars
              |> Map.update({key, :count}, value, fn c -> c + value end)
        }
    }
  end

  def do_start_timing(%{device: %Device{last_tss: last_tss} = device} = state, key)
      when is_atom(key) do
    %{
      state
      | device: %{device | last_tss: last_tss |> Map.put(key, :os.system_time(:micro_seconds))}
    }
  end

  def do_stop_timing(%{device: %Device{last_tss: last_tss} = device} = state, key)
      when is_atom(key) do
    {last_ts, last_tss} =
      last_tss
      |> Map.pop(key)

    %{state | device: %{device | last_tss: last_tss}}
    |> record_hist(:"#{key}_us", :os.system_time(:micro_seconds) - last_ts)
  end

  def do_stop_start_timing(
        %{device: %Device{last_tss: last_tss} = device} = state,
        stop_key,
        start_key
      )
      when is_atom(stop_key) and is_atom(start_key) do
    now_ts = :os.system_time(:micro_seconds)

    {last_ts, last_tss} =
      last_tss
      |> Map.put(start_key, now_ts)
      |> Map.pop(stop_key)

    %{state | device: %{device | last_tss: last_tss}}
    |> record_hist(:"#{stop_key}_us", now_ts - last_ts)
  end

  def record_hist(%{device: %Device{hists: hists} = device} = state, key, value) do
    %{state | device: %{device | hists: Histogram.record(hists, key, value)}}
  end

  defp task_reason_to_key({:timeout, {GenServer, :call, _}}) do
    Logger.debug("Script timeout")

    :timeout_task_error
  end

  defp task_reason_to_key(reason) do
    Logger.error("Script error #{inspect(reason)}")

    :unknown_task_error
  end
end
