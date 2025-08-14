defmodule Stressgrid.Coordinator.GeneratorRegistry do
  @moduledoc false

  use GenServer
  require Logger

  alias Stressgrid.Coordinator.{
    GeneratorRegistry,
    Utils,
    Reporter,
    GeneratorConnection,
    Management
  }

  defstruct registrations: %{},
            monitors: %{},
            generator_next_numeric_id: 0

  def register(id) do
    GenServer.cast(__MODULE__, {:register, id, self()})
  end

  def count do
    GenServer.call(__MODULE__, :count)
  end

  def start_cohort(id, blocks, addresses) do
    GenServer.cast(__MODULE__, {:start_cohort, id, blocks, addresses})
  end

  def stop_cohort(id) do
    GenServer.cast(__MODULE__, {:stop_cohort, id})
  end

  def prepare(blocks) do
    GenServer.call(__MODULE__, {:prepare, blocks})
  end

  defp notify_generators_count(registrations, count) do
    :ok =
      registrations
      |> Enum.each(fn {_, {pid, _}} ->
        :ok = GeneratorConnection.update_generators_count(pid, count)
      end)
  end

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = Management.notify_all(%{"generator_count" => 0})
    {:ok, %GeneratorRegistry{}}
  end

  def handle_call(:count, _from, %GeneratorRegistry{registrations: registrations} = registry) do
    {:reply, map_size(registrations), registry}
  end

  def handle_call(
        {:prepare, blocks},
        _from,
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    registrations
    |> Enum.each(fn {generator_id, {pid, generator_numeric_id}} ->
      :ok =
        GeneratorConnection.prepare(
          pid,
          generator_id,
          generator_numeric_id,
          blocks
        )
    end)

    {:reply, :ok, registry}
  end

  def handle_cast(
        {:register, id, pid},
        %GeneratorRegistry{
          monitors: monitors,
          registrations: registrations,
          generator_next_numeric_id: generator_next_numeric_id
        } = registry
      ) do
    ref = :erlang.monitor(:process, pid)

    Logger.info("Registered generator #{id}")

    registrations =
      Map.put(registrations, id, {pid, generator_next_numeric_id})

    count = map_size(registrations)

    :ok = Management.notify_all(%{"generator_count" => count})
    :ok = notify_generators_count(registrations, count)

    {:noreply,
     %{
       registry
       | generator_next_numeric_id: generator_next_numeric_id + 1,
         registrations: registrations,
         monitors: monitors |> Map.put(ref, id)
     }}
  end

  def handle_cast(
        {:start_cohort, cohort_id, blocks, addresses},
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    :ok =
      registrations
      |> Enum.zip(Utils.split_blocks(blocks, map_size(registrations)))
      |> Enum.each(fn {{generator_id, {pid, generator_numeric_id}}, blocks} ->
        :ok =
          GeneratorConnection.start_cohort(
            pid,
            cohort_id,
            generator_id,
            generator_numeric_id,
            blocks,
            addresses
          )
      end)

    {:noreply, registry}
  end

  def handle_cast(
        {:stop_cohort, id},
        %GeneratorRegistry{registrations: registrations} = registry
      ) do
    :ok =
      registrations
      |> Enum.each(fn {_, {pid, _}} ->
        :ok = GeneratorConnection.stop_cohort(pid, id)
      end)

    {:noreply, registry}
  end

  def handle_info(
        {:DOWN, ref, :process, _, reason},
        %GeneratorRegistry{
          monitors: monitors,
          registrations: registrations
        } = registry
      ) do
    case monitors |> Map.get(ref) do
      nil ->
        {:noreply, registry}

      id ->
        Logger.info("Unregistered generator #{id}: #{inspect(reason)}")

        registrations = Map.delete(registrations, id)
        count = map_size(registrations)

        :ok = Management.notify_all(%{"generator_count" => count})
        :ok = notify_generators_count(registrations, count)
        :ok = Reporter.clear_stats(id)

        {:noreply,
         %{
           registry
           | registrations: registrations,
             monitors: monitors |> Map.delete(ref)
         }}
    end
  end
end
