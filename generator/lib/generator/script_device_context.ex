defmodule Stressgrid.Generator.ScriptDeviceContext do
  @moduledoc false

  alias Stressgrid.Generator.{ScriptDevice}

  defmacro run_script(script) do
    quote do
      result = ScriptDevice.run_script(var!(device_pid), var!(id), unquote(script))

      case result do
        {:ok, script_pid} ->
          script_ref = Process.monitor(script_pid)

          # explicitly wait for the script (genserver) to finish
          receive do
            {:DOWN, ^script_ref, :process, ^script_pid, _reason} -> :ok
          end

        {:error, error} ->
          Process.exit(self(), inspect(error))

          {:error, error}
      end
    end
  end

  # defmodulex avoids module redefinition conflicts when initializing devices, and defins module only once
  # also checks if the module content has changed, and redefines it only if necessary
  defmacro defmodulex(alias, do: block) do
    block_hash = :erlang.phash2(Macro.escape(block))

    quote do
      module_alias = unquote(alias)

      # check if module already exists and if block content has changed
      should_define = case Code.ensure_loaded?(module_alias) do
        false ->
          true
        true ->
          # try to get stored hash from module attribute
          stored_hash = try do
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
end
