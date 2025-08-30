defmodule Mix.Tasks.Stressgrid.Run do
  @moduledoc """
  Run a stress test plan using the Stressgrid coordinator

  This mix task replicates the functionality of the sgcli client but runs
  directly within the coordinator application using internal APIs instead
  of WebSocket connections.

  ## Usage

      mix stressgrid.run <name> <script_file> [options]

  ## Examples

      # Simple script test
      mix stressgrid.run "test" scripts/simple_test.ex --size 100

      # HTTP load test with custom parameters
      mix stressgrid.run "load-test" scripts/http_test.ex \\
        --target-hosts "server1.com,server2.com" \\
        --target-port 8080 \\
        --target-protocol https \\
        --size 5000 \\
        --rampup 300 \\
        --sustain 600 \\
        --rampdown 300

      # UDP test with script parameters
      mix stressgrid.run "udp-test" scripts/udp_test.ex \\
        --target-protocol udp \\
        --script-params '{"message_size": 1024, "rate": 100}'

      # Custom script
      mix stressgrid.run "load-test" "run_script(\"MessagePublish\")" --target-hosts "localhost" --target-protocol script --size 1 --rampup 10 --sustain 100 --rampdown 10

  ## Script Files

  Script files can contain either:

  1. Simple script calls: `run_script("MessagePublish")`
  2. Full Elixir modules implementing the script behavior

  See scripts/simple_test.ex and scripts/http_test.ex for examples.

  ## Options

    * `--target-hosts`, `-t` - Target hosts, comma separated (default: localhost)
    * `--target-port` - Target port (default: 5000)
    * `--target-protocol` - Target protocol: http10|http10s|http|https|http2|http2s|tcp|udp|script (default: http)
    * `--script-params` - Script parameters as JSON (default: {})
    * `--size`, `-s` - Number of devices (default: 10000)
    * `--rampup` - Rampup seconds (default: 900)
    * `--sustain` - Sustain seconds (default: 900)
    * `--rampdown` - Rampdown seconds (default: 900)

  ## Prerequisites

  1. The coordinator application must be running
  2. At least one generator must be connected
  3. Script file must exist and be readable

  ## Output

  The task will display:
  - Generator availability
  - Run configuration details
  - Real-time statistics during execution
  - Final report URLs when complete

  """

  use Mix.Task

  alias Stressgrid.Coordinator.{Scheduler, GeneratorRegistry}

  @switches [
    target_hosts: :string,
    target_port: :integer,
    target_protocol: :string,
    script_params: :string,
    size: :integer,
    rampup: :integer,
    sustain: :integer,
    rampdown: :integer
  ]

  @aliases [
    t: :target_hosts,
    s: :size
  ]

  @impl Mix.Task
  def run(args) do
    {opts, args} = OptionParser.parse!(args, switches: @switches, aliases: @aliases)

    case args do
      [name, script_file | _args] ->
        run_plan(name, script_file, opts)

      _ ->
        Mix.shell().error("Usage: mix stressgrid.run <name> <script_file> [options]")
        System.halt(1)
    end
  end

  defp run_plan(name, script_file, opts) do
    # Start the application if not already started
    Mix.Task.run("app.start")

    script_content =
      if String.contains?(script_file, "script/") do
        unless File.exists?(script_file) do
          Mix.shell().error("Script file not found: #{script_file}")
          System.halt(1)
        end

        File.read!(script_file)
      else
        script_file
      end

    wait_for_generators()

    # Check generator availability
    generator_count = GeneratorRegistry.count()

    if generator_count == 0 do
      Mix.shell().error("No generators available")
      System.halt(1)
    end

    Mix.shell().info("Available generators: #{generator_count}")

    # Parse options with defaults
    target_hosts = Keyword.get(opts, :target_hosts, "localhost")
    target_port = Keyword.get(opts, :target_port, 5000)
    target_protocol = Keyword.get(opts, :target_protocol, "http")
    script_params = parse_script_params(Keyword.get(opts, :script_params, "{}"))
    size = Keyword.get(opts, :size, 10000)
    rampup = Keyword.get(opts, :rampup, 900)
    sustain = Keyword.get(opts, :sustain, 900)
    rampdown = Keyword.get(opts, :rampdown, 900)

    # Calculate ramp steps
    ramp_step_size = generator_count * 10
    ramp_step_size = cond do
      size < ramp_step_size -> 1
      true -> ramp_step_size
    end
    ramp_steps = if ramp_step_size > 0, do: div(size, ramp_step_size), else: 1
    ramp_steps = max(ramp_steps, 1)
    effective_size = ramp_steps * ramp_step_size

    Mix.shell().info("Configured size: #{size}, effective size: #{effective_size}")

    # Build addresses
    addresses = build_addresses(target_hosts, target_port, target_protocol)

    # Build blocks
    blocks = [
      %{
        script: script_content,
        params: script_params,
        size: effective_size
      }
    ]

    # Build opts
    opts_map = [
      ramp_steps: ramp_steps,
      rampup_step_ms: div(rampup * 1000, ramp_steps),
      sustain_ms: sustain * 1000,
      rampdown_step_ms: div(rampdown * 1000, ramp_steps)
    ]

    Mix.shell().info("Starting run: #{name}")
    Mix.shell().info("Target: #{target_hosts}:#{target_port} (#{target_protocol})")
    Mix.shell().info("Ramp: #{rampup}s up, #{sustain}s sustain, #{rampdown}s down")

    # Register for management notifications
    Registry.register(:management_connection_registry, nil, nil)

    # Start the run
    case Scheduler.start_run(name, blocks, addresses, opts_map) do
      :ok ->
        Mix.shell().info("Run started successfully")
        monitor_run(name)

      {:error, reason} ->
        Mix.shell().error("Failed to start run: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp wait_for_generators(timeout_ms \\ 30_000) do
    Mix.shell().info("Waiting for generators to connect...")

    start = System.monotonic_time(:millisecond)
    poll = fn poll_fun ->
      count = GeneratorRegistry.count()
      cond do
        count > 0 ->
          :ok
        System.monotonic_time(:millisecond) - start > timeout_ms ->
          Mix.shell().error("Timeout waiting for generators to connect")
          System.halt(1)
        true ->
          Process.sleep(10)
          poll_fun.(poll_fun)
      end
    end
    poll.(poll)
  end

  defp parse_script_params(params_string) do
    case Jason.decode(params_string) do
      {:ok, params} -> params
      {:error, _} ->
        Mix.shell().error("Invalid JSON in script-params: #{params_string}")
        System.halt(1)
    end
  end

  defp build_addresses(host_string, port, protocol) do
    host_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn host ->
      protocol_atom = String.to_atom(protocol)

      case :inet.gethostbyname(String.to_charlist(host)) do
        {:ok, {:hostent, _, _, _, _, ips}} ->
          Enum.map(ips, fn ip -> {protocol_atom, ip, port, host} end)

        _ ->
          Mix.shell().error("Cannot resolve host: #{host}")
          []
      end
    end)
  end

  defp monitor_run(name) do
    # Set up signal handling for graceful abort
    Process.flag(:trap_exit, true)

    receive do
      {:notify, state} ->
        handle_state_update(state, name)

      {:EXIT, _from, :normal} ->
        :ok

      {:EXIT, _from, reason} ->
        Mix.shell().error("Process exited: #{inspect(reason)}")
    after
      30_000 ->
        Mix.shell().info("Waiting for run to complete...")

        monitor_run(name)
    end
  end

  defp handle_state_update(state, expected_name) do
    case Map.get(state, "run") do
      %{"id" => id, "name" => ^expected_name, "state" => run_state, "remaining_ms" => remaining_ms} ->
        remaining_seconds = div(remaining_ms, 1000)
        Mix.shell().info("Run #{id}: #{run_state} (#{remaining_seconds}s remaining)")

      %{"name" => other_name} ->
        Mix.shell().error("Unexpected run name: #{other_name} (expected: #{expected_name})")
        System.halt(1)

             nil ->
         # Run completed, check for reports
         check_reports(state, expected_name)
         :ok

      _ ->
        :ok
    end

    # Display statistics
    display_stats(Map.get(state, "stats", %{}))

    # Check for script errors
    case Map.get(state, "last_script_error") do
      %{"description" => description} ->
        Mix.shell().error("Script error #{description}")

      _ ->
        :ok
    end

    monitor_run(expected_name)
  end

  defp check_reports(state, expected_name) do
    case Map.get(state, "reports", []) do
      [%{"id" => _id, "name" => ^expected_name, "result" => result} | _] ->
        Mix.shell().info("Run completed successfully!")

        if csv_url = Map.get(result, "csv_url") do
          Mix.shell().info("CSV Report: http://localhost:4000/#{csv_url}")
        end

        if cw_url = Map.get(result, "cw_url") do
          Mix.shell().info("CloudWatch Report: #{cw_url}")
        end

      [] ->
        Mix.shell().info("Run completed (no reports generated)")

      _ ->
        Mix.shell().info("Run completed")
    end
  end

  defp display_stats(stats) when map_size(stats) > 0 do
    stats
    |> Enum.take(5)  # Limit to top 5 stats to avoid spam
    |> Enum.each(fn {key, values} ->
      value = format_stat_value(key, values)
      name = format_stat_name(key)
      Mix.shell().info("  #{name}: #{value}")
    end)
  end

  defp display_stats(_), do: :ok

  defp format_stat_name(key) do
    key
    |> to_string()
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp format_stat_value(key, values) when is_list(values) do
    key = to_string(key)

    case List.first(values) do
      nil -> "-"
      value when is_number(value) ->
        cond do
          String.ends_with?(key, "_bytes_per_second") ->
            format_bytes(value) <> "/sec"

          String.ends_with?(key, "_per_second") ->
            format_number(value) <> " /sec"

          String.ends_with?(key, "_percent") ->
            "#{trunc(value)}%"

          String.ends_with?(key, "_us") ->
            format_time_us(value)

          String.ends_with?(key, "_bytes_count") ->
            format_bytes(value)

          String.ends_with?(key, "_count") ->
            format_number(value)

          true ->
            to_string(value)
        end

      value ->
        to_string(value)
    end
  end

  defp format_bytes(bytes) when bytes >= 1_000_000_000, do: "#{Float.round(bytes / 1_000_000_000, 1)}GB"
  defp format_bytes(bytes) when bytes >= 1_000_000, do: "#{Float.round(bytes / 1_000_000, 1)}MB"
  defp format_bytes(bytes) when bytes >= 1_000, do: "#{Float.round(bytes / 1_000, 1)}KB"
  defp format_bytes(bytes), do: "#{bytes}B"

  defp format_number(num) when num >= 1_000_000, do: "#{Float.round(num / 1_000_000, 1)}M"
  defp format_number(num) when num >= 1_000, do: "#{Float.round(num / 1_000, 1)}K"
  defp format_number(num), do: to_string(trunc(num))

  defp format_time_us(us) when us >= 1_000_000, do: "#{trunc(us / 1_000_000)}s"
  defp format_time_us(us) when us >= 1_000, do: "#{trunc(us / 1_000)}ms"
  defp format_time_us(us), do: "#{us}μs"
end
