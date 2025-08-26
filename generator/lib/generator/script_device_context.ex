defmodule Stressgrid.Generator.ScriptDeviceContext do
  @moduledoc false

  alias Stressgrid.Generator.Scripts

  defmacro run_script(script) do
    quote do
      result = try do
        script_module = Module.concat([Scripts, unquote(script)])

        if Code.ensure_loaded?(script_module) do
          result =
            GenServer.start_link(script_module,
              generator_id: var!(generator_id),
              generator_numeric_id: var!(generator_numeric_id),
              device_id: var!(id),
              device_pid: var!(device_pid),
              device_numeric_id: var!(device_numeric_id)
            )
        else
          {:error, "script module not found #{script_module}"}
        end
      rescue
        error ->
          {:error, error}
      catch
        :exit, reason ->
          {:error, reason}
      end

      case result do
        {:ok, script_pid} ->
          script_ref = Process.monitor(script_pid)

          # explicitly wait for the script (genserver) to finish
          receive do
            {:DOWN, ^script_ref, :process, ^script_pid, reason} ->
              case reason do
                :normal ->
                  :ok

                :shutdown ->
                  :ok

                error ->
                  raise(error)
              end
          end

        {:error, error} ->
          raise(error)
      end
    end
  end

  # defmodulex avoids module redefinition conflicts when initializing devices, and defines module only once
  # also checks if the module content has changed, and redefines it only if necessary
  defmacro defmodulex(alias, do: block) do
    block_hash = :erlang.phash2(block)

    quote do
      module_alias = unquote(alias)

      # check if module already exists and if block content has changed
      should_define =
        case Code.ensure_loaded?(module_alias) do
          false ->
            true

          true ->
            # try to get stored hash from module attribute
            stored_hash =
              try do
                module_alias.__hash__()
              rescue
                _ -> nil
              end

            stored_hash != unquote(block_hash)
        end

      if should_define do
        # purge existing module if it exists
        if Code.ensure_loaded?(module_alias) do
          :code.purge(module_alias)
          :code.delete(module_alias)
        end

        defmodule module_alias do
          def __hash__(), do: unquote(block_hash)

          unquote(block)
        end
      end
    end
  end

  defmacro defmodule_noop(_alias, do: _block) do
   # do nothing, modules defined only in prepare_script using defmodulex macros
  end
end
