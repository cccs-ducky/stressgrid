defmodule Stressgrid.Coordinator.GeneratorConnection do
  @moduledoc false

  @behaviour :cowboy_websocket

  require Logger

  defstruct id: nil

  alias Stressgrid.Coordinator.{
    GeneratorConnection,
    Reporter,
    GeneratorRegistry
  }

  def start_cohort(pid, id, generator_id, generator_numeric_id, blocks, addresses) do
    send_terms(pid, [
      {:start_cohort,
       %{
         id: id,
         generator_id: generator_id,
         generator_numeric_id: generator_numeric_id,
         blocks: blocks,
         addresses: addresses
       }}
    ])
  end

  def stop_cohort(pid, id) do
    send_terms(pid, [
      {:stop_cohort, %{id: id}}
    ])
  end

  def update_generators_count(pid, count) do
    send_terms(pid, [
      {:update_generators_count, %{count: count}}
    ])
  end

  def init(req, _) do
    {:cowboy_websocket, req, %GeneratorConnection{}}
  end

  def websocket_init(%GeneratorConnection{} = connection) do
    {:ok, connection}
  end

  def websocket_handle({:binary, frame}, connection) do
    connection =
      :erlang.binary_to_term(frame)
      |> Enum.reduce(connection, &receive_term(&2, &1))

    {:ok, connection}
  end

  def websocket_info({:send, terms}, connection) do
    {:reply, {:binary, :erlang.term_to_binary(terms)}, connection}
  end

  defp receive_term(connection, {:register, %{id: id}}) do
    :ok = GeneratorRegistry.register(id)
    %{connection | id: id}
  end

  defp receive_term(
         %GeneratorConnection{id: id} = connection,
         {:push_telemetry, telemetry}
       ) do
    :ok = Reporter.push_telemetry(id, telemetry)
    connection
  end

  defp send_terms(pid, terms) when is_list(terms) do
    _ = Kernel.send(pid, {:send, terms})
    :ok
  end
end
