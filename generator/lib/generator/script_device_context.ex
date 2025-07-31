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
          {:error, error}
      end
    end
  end
end
