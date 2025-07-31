defmodule Stressgrid.Generator.ScriptGenServer do
  defmacro __using__(_opts) do
    quote do
      use GenServer

      import unquote(__MODULE__)

      @spec start_link(any()) :: GenServer.on_start()
      def start_link(args) do
        GenServer.start_link(
          __MODULE__,
          args,
          name: "#{__MODULE__}-#{:erlang.unique_integer([:monotonic, :positive])}"
        )
      end

      @impl true
      def init(args) do
        device_id = Keyword.fetch!(args, :device_id)
        device_pid = Keyword.fetch!(args, :device_pid)

        Process.put(:device_id, device_id)
        Process.put(:device_pid, device_pid)

        do_init(%{device_id: device_id, device_pid: device_pid})
      end
    end
  end
end
