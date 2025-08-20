defmodule Finch.TelemetryHandler do
  @moduledoc """
  Telemetry handler for Finch that tracks events and pushes metrics
  using the device context's inc_counter functionality.
  """

  import Stressgrid.Generator.DeviceContext

  @doc """
  Attaches telemetry handlers for all Finch events.
  Call this in your script's do_init/1 function.
  """
  def attach_handlers(device_pid) do
    events = [
      # Request lifecycle events
      [:finch, :request, :start],
      [:finch, :request, :stop],
      [:finch, :request, :exception],

      # Queue events (HTTP1 connection pool)
      [:finch, :queue, :start],
      [:finch, :queue, :stop],
      [:finch, :queue, :exception],

      # Connection lifecycle events
      [:finch, :connect, :start],
      [:finch, :connect, :stop],

      # Send/receive events
      [:finch, :send, :start],
      [:finch, :send, :stop],
      [:finch, :recv, :start],
      [:finch, :recv, :stop],
      [:finch, :recv, :exception],

      # Connection reuse and timeout events
      [:finch, :reused_connection],
      [:finch, :conn_max_idle_time_exceeded],
      [:finch, :pool_max_idle_time_exceeded],
      [:finch, :max_idle_time_exceeded]
    ]

    :telemetry.attach_many(
      "finch_metrics",
      events,
      &__MODULE__.handle_event/4,
      %{
        device_pid: device_pid
      }
    )
  end

  def detach_handlers do
    :telemetry.detach("finch_metrics")
  end

  def handle_event(event, measurements, metadata, %{ device_pid: device_pid } = config) do
    Process.put(:device_pid, device_pid)

    do_handle_event(event, measurements, metadata, config)
  end

  def do_handle_event([:finch, :request, :start], _measurements, _metadata, _config) do
    inc_counter(:finch_requests_started, 1)
  end

  def do_handle_event([:finch, :request, :stop], measurements, _metadata, _config) do
    inc_counter(:finch_requests_completed, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_request, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :request, :exception], measurements, _metadata, _config) do
    inc_counter(:finch_request_exceptions, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_request, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :queue, :start], _measurements, _metadata, _config) do
    inc_counter(:finch_queue_started, 1)
  end

  def do_handle_event([:finch, :queue, :stop], measurements, _metadata, _config) do
    inc_counter(:finch_queue_completed, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_queue, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :queue, :exception], measurements, _metadata, _config) do
    inc_counter(:finch_queue_exceptions, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_queue, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :connect, :start], _measurements, _metadata, _config) do
    inc_counter(:finch_connections_started, 1)
  end

  def do_handle_event([:finch, :connect, :stop], measurements, _metadata, _config) do
    inc_counter(:finch_connections_completed, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_connect, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :send, :start], _measurements, _metadata, _config) do
    inc_counter(:finch_sends_started, 1)
  end

  def do_handle_event([:finch, :send, :stop], measurements, _metadata, _config) do
    inc_counter(:finch_sends_completed, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_send, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :recv, :start], _measurements, _metadata, _config) do
    inc_counter(:finch_receives_started, 1)
  end

  def do_handle_event([:finch, :recv, :stop], measurements, metadata, _config) do
    inc_counter(:finch_receives_completed, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_receive, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end

    # Track HTTP status codes if available
    if Map.has_key?(metadata, :status) do
      inc_counter(:"finch_status_#{metadata.status}", 1)

      # Group status codes by class (2xx, 3xx, 4xx, 5xx)
      status_class = div(metadata.status, 100)
      inc_counter(:"finch_status_#{status_class}xx", 1)
    end
  end

  def do_handle_event([:finch, :recv, :exception], measurements, _metadata, _config) do
    inc_counter(:finch_receive_exceptions, 1)

    if Map.has_key?(measurements, :duration) do
      record_timing(:finch_receive, System.convert_time_unit(measurements.duration, :native, :microsecond))
    end
  end

  def do_handle_event([:finch, :reused_connection], _measurements, _metadata, _config) do
    inc_counter(:finch_connections_reused, 1)
  end

  def do_handle_event([:finch, :conn_max_idle_time_exceeded], _measurements, _metadata, _config) do
    inc_counter(:finch_connections_idle_timeout, 1)
  end

  def do_handle_event([:finch, :pool_max_idle_time_exceeded], _measurements, _metadata, _config) do
    inc_counter(:finch_pools_idle_timeout, 1)
  end

  def do_handle_event([:finch, :max_idle_time_exceeded], _measurements, _metadata, _config) do
    inc_counter(:finch_connections_idle_timeout_deprecated, 1)
  end

  # Fallback for any unhandled events
  def do_handle_event(_event, _measurements, _metadata, _config) do
    :ok
  end
end
