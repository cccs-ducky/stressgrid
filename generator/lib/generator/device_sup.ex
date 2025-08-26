defmodule Stressgrid.Generator.Device.Supervisor do
  @moduledoc false

  use DynamicSupervisor

  alias Stressgrid.Generator.{GunDevice, TcpDevice, UdpDevice, ScriptDevice}

  def start_link([]) do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def start_child(cohort_pid, id, generator_id, generator_numeric_id, address, script, params) do
    device_numeric_id = :atomics.add_get(:persistent_term.get(:sg_device_counter), 1, 1) - 1

    DynamicSupervisor.start_child(
      cohort_pid,
      {address_module(address),
       id: id,
       device_numeric_id: device_numeric_id,
       generator_id: generator_id,
       generator_numeric_id: generator_numeric_id,
       address: address,
       script: script,
       params: params}
    )
  end

  def init(_) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  defp address_module({:http10, _, _, _}), do: GunDevice
  defp address_module({:http10s, _, _, _}), do: GunDevice
  defp address_module({:http, _, _, _}), do: GunDevice
  defp address_module({:https, _, _, _}), do: GunDevice
  defp address_module({:http2, _, _, _}), do: GunDevice
  defp address_module({:http2s, _, _, _}), do: GunDevice
  defp address_module({:tcp, _, _, _}), do: TcpDevice
  defp address_module({:udp, _, _, _}), do: UdpDevice
  defp address_module({:script, _, _, _}), do: ScriptDevice
end
