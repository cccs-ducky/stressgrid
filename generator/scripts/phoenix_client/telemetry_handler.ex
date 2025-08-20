defmodule PhoenixClient.TelemetryHandler do
  @moduledoc """
  Telemetry handler for PhoenixClient that tracks events and pushes metrics
  using the device context's inc_counter functionality.
  """

  import Stressgrid.Generator.DeviceContext

  @doc """
  Attaches telemetry handlers for all PhoenixClient events.
  Call this in your script's do_init/1 function.
  """
  def attach_handlers(device_pid) do
    events = [
      # Connection lifecycle events
      [:phoenix_client, :connection, :attempt],
      [:phoenix_client, :connection, :connected],
      [:phoenix_client, :connection, :disconnected],
      [:phoenix_client, :connection, :closed],
      [:phoenix_client, :connection, :failed],
      [:phoenix_client, :connection, :reconnect_scheduled],
      [:phoenix_client, :connection, :closed_permanently],

      # Channel lifecycle events
      [:phoenix_client, :channel, :joined],
      [:phoenix_client, :channel, :left],
      [:phoenix_client, :channel, :down],

      # Message handling events
      [:phoenix_client, :message, :pushed],
      [:phoenix_client, :message, :sent],
      [:phoenix_client, :message, :received]
    ]

    :telemetry.attach_many(
      "phoenix_client_metrics",
      events,
      &__MODULE__.handle_event/4,
      %{
        device_pid: device_pid
      }
    )
  end

  def detach_handlers do
    :telemetry.detach("phoenix_client_metrics")
  end

  def handle_event(event, measurements, metadata, %{ device_pid: device_pid } = config) do
    Process.put(:device_pid, device_pid)

    do_handle_event(event, measurements, metadata, config)
  end

  defp do_handle_event([:phoenix_client, :connection, :attempt], _measurements, _metadata, _config) do
    inc_counter(:phoenix_connection_attempts, 1)
  end

  defp do_handle_event([:phoenix_client, :connection, :connected], _measurements, _metadata, _config) do
    inc_counter(:phoenix_connections, 1)
  end

  defp do_handle_event(
        [:phoenix_client, :connection, :disconnected],
        _measurements,
        _metadata,
        _config
      ) do
    inc_counter(:phoenix_disconnections, 1)
  end

  defp do_handle_event([:phoenix_client, :connection, :closed], _measurements, _metadata, _config) do
    inc_counter(:phoenix_connection_closed, 1)
  end

  defp do_handle_event([:phoenix_client, :connection, :failed], _measurements, _metadata, _config) do
    inc_counter(:phoenix_connection_failures, 1)
  end

  defp do_handle_event(
        [:phoenix_client, :connection, :reconnect_scheduled],
        _measurements,
        _metadata,
        _config
      ) do
    inc_counter(:phoenix_reconnects_scheduled, 1)
  end

  defp do_handle_event(
        [:phoenix_client, :connection, :closed_permanently],
        _measurements,
        _metadata,
        _config
      ) do
    inc_counter(:phoenix_connections_closed_permanently, 1)
  end

  defp do_handle_event([:phoenix_client, :channel, :joined], _measurements, _metadata, _config) do
    inc_counter(:phoenix_channel_joins, 1)
  end

  defp do_handle_event([:phoenix_client, :channel, :left], _measurements, _metadata, _config) do
    inc_counter(:phoenix_channel_leaves, 1)
  end

  defp do_handle_event([:phoenix_client, :channel, :down], _measurements, _metadata, _config) do
    inc_counter(:phoenix_channel_crashes, 1)
  end

  defp do_handle_event([:phoenix_client, :message, :pushed], _measurements, _metadata, _config) do
    inc_counter(:phoenix_messages_pushed, 1)
  end

  defp do_handle_event([:phoenix_client, :message, :sent], _measurements, _metadata, _config) do
    inc_counter(:phoenix_messages_sent, 1)
  end

  defp do_handle_event([:phoenix_client, :message, :received], _measurements, _metadata, _config) do
    inc_counter(:phoenix_messages_received, 1)
  end

  # Fallback for any unhandled events
  defp do_handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
