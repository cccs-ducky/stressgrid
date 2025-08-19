defmodule Stressgrid.Generator.ScriptDevice do
  @moduledoc false

  alias Stressgrid.Generator.{
    Device,
    ScriptDevice,
    ScriptDeviceContext
  }

  use GenServer

  use Device,
    device_macros: [
      {ScriptDeviceContext,
       [
         run_script: 1,
         defmodulex: 2,
         defmodule_noop: 2
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
end
