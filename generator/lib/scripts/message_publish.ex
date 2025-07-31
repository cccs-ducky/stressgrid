defmodule Stressgrid.Generator.Scripts.MessagePublish do
  use Stressgrid.Generator.ScriptGenServer

  require Logger

  import Stressgrid.Generator.DeviceContext

  @interval 100

  def do_init(state) do
    Process.send_after(self(), :tick, @interval)
    Process.send_after(self(), :shutdown, 5_000)

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    inc_counter(:messages_published, 1)

    Process.send_after(self(), :tick, @interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:shutdown, state) do
    Logger.info("Shutting down MessagePublish script for device #{state.device_id}")

    {:stop, :normal, state}
  end
end
