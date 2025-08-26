defmodule Stressgrid.Generator.ScriptGenServer do
  defmacro __using__(_opts) do
    quote location: :keep do
      use GenServer

      @spec start_link(any()) :: GenServer.on_start()
      def start_link(args) do
        GenServer.start_link(
          __MODULE__,
          args,
          name: "#{__MODULE__}-#{Keyword.fetch!(args, :device_numeric_id)}"
        )
      end

      @impl true
      def init(args) do
        device_id = Keyword.fetch!(args, :device_id)
        device_pid = Keyword.fetch!(args, :device_pid)
        device_numeric_id = Keyword.fetch!(args, :device_numeric_id)
        generator_id = Keyword.fetch!(args, :generator_id)
        generator_numeric_id = Keyword.fetch!(args, :generator_numeric_id)

        Process.put(:device_id, device_id)
        Process.put(:device_pid, device_pid)
        Process.put(:device_numeric_id, device_numeric_id)
        Process.put(:generator_id, generator_id)
        Process.put(:generator_numeric_id, generator_numeric_id)

        case do_init(%{
               device_id: device_id,
               device_pid: device_pid,
               device_numeric_id: device_numeric_id,
               generator_id: generator_id,
               generator_numeric_id: generator_numeric_id
             }) do
          {:ok, state} ->
            {:ok, state, {:continue, :run}}

          result ->
            result
        end
      end

      @impl true
      def handle_continue(:run, state) do
        run(state)
      end
    end
  end
end
