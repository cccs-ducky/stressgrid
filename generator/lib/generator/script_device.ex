defmodule Stressgrid.Generator.ScriptDevice do
  @moduledoc false

  alias Stressgrid.Generator.{
    Device,
    ScriptDevice,
    ScriptDeviceContext,
    Scripts
  }

  use GenServer

  use Device,
    device_macros: [
      {ScriptDeviceContext,
       [
         run_script: 1
       ]
       |> Enum.sort()}
    ]

  require Logger

  defstruct []

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    {:ok, %ScriptDevice{} |> Device.init(args)}
  end

  def open(%ScriptDevice{} = device) do
    device |> Device.start_task()
  end

  def close(%ScriptDevice{} = device) do
    device
  end

  def run_script(device_pid, device_id, script) do
    if Process.alive?(device_pid) do
      GenServer.call(device_pid, {:run_script, script, %{ device_id: device_id, device_pid: device_pid }}, :infinity)
    else
      exit(:device_terminated)
    end
  end

  def handle_call(
        {:run_script, script, %{ device_id: device_id, device_pid: device_pid }},
        _,
        %ScriptDevice{} = device
      ) do
    result = GenServer.start(Module.concat([Scripts, script]), device_id: device_id, device_pid: device_pid)

    {:reply, result, device}
  rescue
    error ->
      {:reply, {:error, error}, device}
  end
end
