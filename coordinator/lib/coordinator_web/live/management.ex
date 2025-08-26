defmodule Stressgrid.CoordinatorWeb.ManagementLive do
  use Stressgrid.CoordinatorWeb, :live_view

  alias Stressgrid.Coordinator.{Management, Scheduler, Reporter}

  @default_script """
  run_script("HttpRequestDemo")
  """

  @default_json """
  {
    "name": "10k",
    "addresses": [
      {
        "host": "localhost",
        "port": 5000,
        "protocol": "script"
      }
    ],
    "blocks": [
      {
        "script": #{@default_script},
        "params": {},
        "size": 10000
      }
    ],
    "opts": {
      "ramp_steps": 1000,
      "rampup_step_ms": 900,
      "sustain_ms": 900000,
      "rampdown_step_ms": 900
    }
  }
  """

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Management.connect()
    end

    {:ok,
     assign(socket,
       state: %{},
       plan_modal: false,
       advanced: false,
       error: nil,
       name: "10k",
       host: "localhost",
       port: "5000",
       protocol: "script",
       script: @default_script,
       params: "{}",
       desired_size: "10000",
       rampup_secs: "900",
       sustain_secs: "900",
       rampdown_secs: "900",
       json: @default_json
     )}
  end

  def handle_info({:notify, state}, socket) do
    {:noreply, assign(socket, :state, format_state(Map.merge(socket.assigns.state, state)))}
  end

  defp format_state(state) do
    %{
      state
      | "stats" =>
          state
          |> Map.get("stats", %{})
          |> Map.new(fn {k, v} -> {if(is_atom(k), do: Atom.to_string(k), else: k), v} end)
    }
  end

  def handle_event("load_settings", settings, socket) do
    {:noreply,
     assign(socket, settings |> Enum.into(%{}, fn {k, v} -> {String.to_atom(k), v} end))}
  end

  def handle_event("show_plan_modal", _params, socket) do
    {:noreply, assign(socket, plan_modal: true, error: nil)}
  end

  def handle_event("hide_plan_modal", _params, socket) do
    {:noreply, assign(socket, plan_modal: false)}
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply,
     assign(socket, advanced: not socket.assigns.advanced)
     |> push_event("save_settings", %{advanced: not socket.assigns.advanced})}
  end

  def handle_event("update_form", %{"_target" => [field]} = params, socket) do
    value = Map.fetch!(params, field)

    {:noreply,
     assign(socket, String.to_atom(field), value)
     |> push_event("save_settings", %{field => value})}
  end

  def handle_event("start_run", params, socket) do
    case build_run_plan(params, socket.assigns) do
      {:ok, plan} ->
        send_websocket_message([%{"start_run" => plan}])
        {:noreply, assign(socket, plan_modal: false, error: nil)}

      {:error, error} ->
        {:noreply, assign(socket, error: error)}
    end
  end

  def handle_event("abort_run", _params, socket) do
    send_websocket_message(["abort_run"])
    {:noreply, socket}
  end

  def handle_event("remove_report", %{"id" => id}, socket) do
    send_websocket_message([%{"remove_report" => %{"id" => id}}])
    {:noreply, socket}
  end

  defp build_run_plan(%{"advanced" => "true", "json" => json}, _assigns) do
    case Jason.decode(json) do
      {:ok, plan} -> {:ok, plan}
      {:error, _} -> {:error, "Invalid JSON"}
    end
  end

  defp build_run_plan(_params, assigns) do
    with {:ok, size} <- parse_int(assigns.desired_size, %{ key: "desired_size" }),
         {:ok, port} <- parse_int(assigns.port || "80", %{ key: "port" }),
         {:ok, rampup} <- parse_int(assigns.rampup_secs, %{ key: "rampup_secs" }),
         {:ok, sustain} <- parse_int(assigns.sustain_secs, %{ key: "sustain_secs" }),
         {:ok, rampdown} <- parse_int(assigns.rampdown_secs, %{ key: "rampdown_secs" }),
         {:ok, params_obj} <- parse_json(assigns.params || "{}", %{ key: "params" }) do
      generator_count = Map.get(assigns.state, "generator_count", 0)
      ramp_step_size = generator_count * 10
      ramp_step_size = cond do
        size < ramp_step_size -> 1
        true -> ramp_step_size
      end
      ramp_steps = if ramp_step_size > 0, do: div(size, ramp_step_size), else: 1
      ramp_steps = max(ramp_steps, 1)
      effective_size = ramp_steps * ramp_step_size

      plan = %{
        "name" => assigns.name,
        "addresses" => build_addresses(assigns.host || "localhost", port, assigns.protocol),
        "blocks" => [
          %{
            "script" => assigns.script,
            "params" => params_obj,
            "size" => effective_size
          }
        ],
        "opts" => %{
          "ramp_steps" => ramp_steps,
          "rampup_step_ms" => div(rampup * 1000, ramp_steps),
          "sustain_ms" => sustain * 1000,
          "rampdown_step_ms" => div(rampdown * 1000, ramp_steps)
        }
      }

      {:ok, plan}
    else
      {:error, msg} -> {:error, msg}
    end
  end

  defp build_addresses(host_string, port, protocol) do
    host_string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(fn host ->
      %{
        "host" => host,
        "port" => port,
        "protocol" => protocol
      }
    end)
  end

  defp parse_int(value, context) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, Map.merge(context, %{error: "invalid number: #{value}"}) |> inspect()}
    end
  end

  defp parse_int(value, context) do
    {:error, Map.merge(context, %{error: "invalid number: #{value}"}) |> inspect()}
  end

  defp parse_json(value, context) do
    Jason.decode(value)
  rescue
    error ->
      {:error, Map.merge(context, %{error: "invalid JSON: #{value}", orig_error: error}) |> inspect()}
  end

  defp send_websocket_message(message) do
    case message do
      [%{"start_run" => plan}] ->
        name = Map.get(plan, "name")
        blocks = convert_blocks(Map.get(plan, "blocks", []))
        addresses = convert_addresses(Map.get(plan, "addresses", []))
        opts = convert_opts(Map.get(plan, "opts", %{}))

        Scheduler.start_run(name, blocks, addresses, opts)

      ["abort_run"] ->
        Scheduler.abort_run()

      [%{"remove_report" => %{"id" => id}}] ->
        Reporter.remove_report(id)

      _ ->
        :ok
    end
  end

  defp convert_blocks(blocks_json) do
    Enum.map(blocks_json, fn block ->
      %{
        script: Map.get(block, "script", ""),
        params: Map.get(block, "params", %{}),
        size: Map.get(block, "size", 0)
      }
    end)
  end

  defp convert_addresses(addresses_json) do
    Enum.flat_map(addresses_json, fn address ->
      host = Map.get(address, "host")
      port = Map.get(address, "port", 80)
      protocol = String.to_atom(Map.get(address, "protocol", "http"))

      case :inet.gethostbyname(String.to_charlist(host)) do
        {:ok, {:hostent, _, _, _, _, ips}} ->
          Enum.map(ips, fn ip -> {protocol, ip, port, host} end)

        _ ->
          []
      end
    end)
  end

  defp convert_opts(opts_json) do
    [
      ramp_steps: Map.get(opts_json, "ramp_steps", 1),
      rampup_step_ms: Map.get(opts_json, "rampup_step_ms", 1000),
      sustain_ms: Map.get(opts_json, "sustain_ms", 60000),
      rampdown_step_ms: Map.get(opts_json, "rampdown_step_ms", 1000)
    ]
  end

  def render(assigns) do
    ~H"""
    <div id="settings-storage" class="container mx-auto p-4 max-w-7xl"
         phx-hook="SettingsStorage">
      <!-- Plan Modal -->
      <%= if @plan_modal do %>
        <div id="plan-modal" phx-hook="PlanModal" class="fixed inset-0 bg-gray-600 bg-opacity-50 dark:bg-gray-900 dark:bg-opacity-80 overflow-y-auto h-full w-full z-50">
          <div class="relative top-20 mx-auto p-5 border w-11/12 max-w-4xl shadow-lg rounded-md bg-white dark:bg-gray-800 dark:border-gray-700">
            <div class="mt-3">
              <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100 mb-4">Start Load Test</h3>

              <%= if @error do %>
                <div class="mb-4 bg-red-50 border border-red-200 text-red-700 dark:bg-red-900 dark:border-red-700 dark:text-red-200 px-4 py-3 rounded">
                  <%= @error %>
                </div>
              <% end %>

              <form phx-submit="start_run">
                <div class="mb-4">
                  <label class="flex items-center">
                    <input
                      type="checkbox"
                      class="rounded border-gray-300 text-blue-600 dark:border-gray-600 dark:bg-gray-700"
                      phx-click="toggle_advanced"
                      checked={@advanced}
                    />
                    <span class="ml-2 text-sm text-gray-700 dark:text-gray-200">Advanced Mode</span>
                  </label>
                </div>

                <%= if @advanced do %>
                  <div class="mb-4">
                    <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">JSON Configuration</label>
                    <div id="json-editor-container" phx-hook="CodeEditor" phx-update="ignore" data-lang="json" data-field="json">
                      <textarea
                        id="json-editor"
                        name="json"
                        class="w-full min-h-96 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                        style="field-sizing: content"
                        phx-change="update_form"
                        phx-value-field="json"
                      ><%= @json %></textarea>
                    </div>
                  </div>
                <% else %>
                  <div class="space-y-4">
                    <!-- Basic Configuration -->
                    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Run Name</label>
                        <input
                          type="text"
                          name="name"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@name}
                          phx-change="update_form"
                          phx-value-field="name"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Desired Devices</label>
                        <input
                          type="number"
                          name="desired_size"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@desired_size}
                          min="0"
                          phx-change="update_form"
                          phx-value-field="desired_size"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Effective Devices</label>
                        <input
                          type="text"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md bg-gray-50 dark:bg-gray-800 dark:border-gray-700 dark:text-gray-100"
                          value={calculate_effective_size(@state, @desired_size)}
                          readonly
                        />
                        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">
                          Multiples of ramp step size: <%= calculate_ramp_step_size(@state) %>
                        </p>
                      </div>
                    </div>

                    <!-- Target Configuration -->
                    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Protocol</label>
                        <select
                          name="protocol"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          phx-change="update_form"
                          phx-value-field="protocol"
                        >
                          <%= for {value, label} <- protocol_options() do %>
                            <option value={value} selected={@protocol == value}><%= label %></option>
                          <% end %>
                        </select>
                      </div>
                      <%= unless @protocol == "script" do %>
                        <div>
                          <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Target Host(s)</label>
                          <input
                            type="text"
                            name="host"
                            class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                            value={@host}
                            phx-change="update_form"
                            phx-value-field="host"
                          />
                          <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">Comma separated</p>
                        </div>
                      <% end %>
                      <%= unless @protocol == "script" do %>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Target Port</label>
                        <input
                          type="number"
                          name="port"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@port}
                          phx-change="update_form"
                          phx-value-field="port"
                        />
                      </div>
                      <% end %>
                    </div>

                    <!-- Timing Configuration -->
                    <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Rampup (seconds)</label>
                        <input
                          type="number"
                          name="rampup_secs"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@rampup_secs}
                          min="0"
                          phx-change="update_form"
                          phx-value-field="rampup_secs"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Sustain (seconds)</label>
                        <input
                          type="number"
                          name="sustain_secs"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@sustain_secs}
                          min="0"
                          phx-change="update_form"
                          phx-value-field="sustain_secs"
                        />
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Rampdown (seconds)</label>
                        <input
                          type="number"
                          name="rampdown_secs"
                          class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                          value={@rampdown_secs}
                          min="0"
                          phx-change="update_form"
                          phx-value-field="rampdown_secs"
                        />
                      </div>
                    </div>

                    <!-- Script and Parameters -->
                    <div class="space-y-4">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Script</label>
                        <div id="script-editor-container" phx-hook="CodeEditor" phx-update="ignore" data-lang="elixir" data-field="script">
                          <textarea
                            id="script-editor"
                            name="script"
                            class="w-full min-h-32 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                            style="field-sizing: content"
                            phx-change="update_form"
                            phx-value-field="script"
                          ><%= @script %></textarea>
                        </div>
                        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">Elixir</p>
                      </div>
                      <div>
                        <label class="block text-sm font-medium text-gray-700 dark:text-gray-200 mb-2">Parameters</label>
                        <div id="params-editor-container" phx-hook="CodeEditor" phx-update="ignore" data-lang="json" data-field="params">
                          <textarea
                            id="params-editor"
                            name="params"
                            class="w-full min-h-32 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono text-sm dark:bg-gray-900 dark:border-gray-700 dark:text-gray-100"
                            style="field-sizing: content"
                            phx-change="update_form"
                            phx-value-field="params"
                          ><%= @params %></textarea>
                        </div>
                        <p class="text-xs text-gray-500 dark:text-gray-400 mt-1">JSON</p>
                      </div>
                    </div>
                  </div>
                <% end %>

                <input type="hidden" name="advanced" value={@advanced} />

                <div class="flex justify-end space-x-2 pt-4">
                  <button
                    type="button"
                    class="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 dark:bg-gray-800 dark:text-gray-200 dark:border-gray-700 dark:hover:bg-gray-700"
                    phx-click="hide_plan_modal"
                  >
                    Cancel
                  </button>
                  <button
                    type="submit"
                    class="px-4 py-2 text-sm font-medium text-white bg-blue-600 border border-transparent rounded-md hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800"
                  >
                    Start
                  </button>
                </div>
              </form>
            </div>
          </div>
        </div>
      <% end %>

      <!-- Main Dashboard -->
      <div class="grid grid-cols-1 lg:grid-cols-3 gap-6 items-start">
        <!-- Status Panel -->
        <div class="bg-white shadow rounded-lg dark:bg-gray-800 dark:shadow-lg lg:col-span-2">
          <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100">Run</h3>
          </div>
          <div class="p-6">
            <div class="space-y-4">
              <!-- Current Run -->
              <div class="flex justify-between items-center">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-200">Current Run</span>
                <div id="current-run" class="flex items-center space-x-3" phx-hook="CurrentRun">
                  <%= if get_in(@state, ["run", "id"]) do %>
                    <span class="text-sm text-gray-900 dark:text-gray-100"><%= get_in(@state, ["run", "id"]) %></span>
                    <button
                      class="px-3 py-1 text-xs font-medium text-white bg-red-600 rounded hover:bg-red-700 dark:bg-red-700 dark:hover:bg-red-800"
                      phx-click="abort_run"
                    >
                      Abort
                    </button>
                  <% else %>
                    <button
                      class="px-3 py-1 text-xs font-medium text-white bg-blue-600 rounded hover:bg-blue-700 dark:bg-blue-700 dark:hover:bg-blue-800"
                      phx-click="show_plan_modal"
                    >
                      Start
                    </button>
                  <% end %>
                </div>
              </div>

              <!-- State -->
              <div class="flex justify-between items-center">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-200">State</span>
                <div class="flex items-center space-x-3">
                  <span class="text-sm font-semibold text-gray-900 dark:text-gray-100">
                    <%= get_in(@state, ["run", "state"]) || "idle" %>
                  </span>
                  <%= if get_in(@state, ["run", "remaining_ms"]) do %>
                    <span class="text-sm text-gray-600 dark:text-gray-400">
                      <%= div(get_in(@state, ["run", "remaining_ms"]), 1000) %> seconds remaining
                    </span>
                  <% end %>
                </div>
              </div>

              <!-- Generators -->
              <div class="flex justify-between items-center">
                <span class="text-sm font-medium text-gray-700 dark:text-gray-200">Generators</span>
                <span class="text-sm text-gray-900 dark:text-gray-100"><%= Map.get(@state, "generator_count", 0) %></span>
              </div>

              <!-- Script Error -->
              <%= if get_in(@state, ["last_script_error"]) do %>
                <div class="flex justify-between items-start">
                  <span class="text-sm font-medium text-gray-700 dark:text-gray-200">Script Error</span>
                  <div class="flex items-center space-x-2">
                    <span class="text-sm text-red-600 dark:text-red-400 max-w-xs">
                      <%= get_in(@state, ["last_script_error", "description"]) %>
                    </span>
                    <svg class="w-4 h-4 text-red-500 dark:text-red-400" fill="currentColor" viewBox="0 0 20 20">
                      <path fill-rule="evenodd" d="M3 6a3 3 0 013-3h10a1 1 0 01.8 1.6L14.25 8l2.55 3.4A1 1 0 0116 13H6a1 1 0 00-1 1v3a1 1 0 11-2 0V6z" clip-rule="evenodd"></path>
                    </svg>
                  </div>
                </div>
              <% end %>

              <!-- Statistics -->
              <%= for {key, values} <- Map.get(@state, "stats", %{}) |> Enum.sort_by(fn {k, _v} -> k end) do %>
                <% metric_type = get_metric_type(key) %>
                <div class="flex justify-between items-center">
                  <div class="flex w-full">
                    <div class="flex-1 min-w-0">
                      <span class={["text-sm break-all", get_metric_colors(metric_type)]}><%= format_stat_name(key) %></span>
                    </div>
                    <div class="flex-none flex items-center space-x-3">
                      <span class={["text-sm", get_value_colors(metric_type)]}><%= format_stat_value(key, values) %></span>
                      <%= if key == "cpu_percent" do %>
                        <svg class={["w-4 h-4", if(is_red_cpu?(values), do: "text-red-500 dark:text-red-400", else: "text-green-500 dark:text-green-400")]} fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"></path>
                        </svg>
                      <% end %>
                      <%= if is_error_stat?(key) do %>
                        <svg class="w-4 h-4 text-red-500 dark:text-red-400" fill="currentColor" viewBox="0 0 20 20">
                          <path fill-rule="evenodd" d="M3 6a3 3 0 013-3h10a1 1 0 01.8 1.6L14.25 8l2.55 3.4A1 1 0 0116 13H6a1 1 0 00-1 1v3a1 1 0 11-2 0V6z" clip-rule="evenodd"></path>
                        </svg>
                      <% end %>
                    </div>
                    <div class="flex items-center flex-none ml-4">
                      <div id={"sparkline-#{key}"} data-points={sparkline_data(values)} phx-hook="Sparkline" phx-update="ignore" style="width: 220px; height: 20px;"></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Reports Panel -->
        <div class="bg-white shadow rounded-lg dark:bg-gray-800 dark:shadow-lg">
          <div class="px-6 py-4 border-b border-gray-200 dark:border-gray-700">
            <h3 class="text-lg font-medium text-gray-900 dark:text-gray-100">Reports</h3>
          </div>
          <div class="p-6">
            <%= if Map.get(@state, "reports") != [] do %>
              <div class="space-y-3">
                <%= for report <- Map.get(@state, "reports", []) do %>
                  <div class="border border-gray-200 rounded-lg p-4 dark:border-gray-700">
                    <div class="flex justify-between items-start">
                      <div class="flex-1">
                        <div class="flex items-center space-x-2">
                          <span class="text-sm font-medium text-gray-900 dark:text-gray-100"><%= Map.get(report, "id") %></span>
                        </div>
                        <div class="mt-2 flex items-center space-x-4">
                          <div class="flex items-center space-x-1">
                            <span class="text-xs text-gray-500 dark:text-gray-400">Errors</span>
                            <svg class={["w-4 h-4", if(has_errors?(report), do: "text-red-500 dark:text-red-400", else: "text-green-500 dark:text-green-400")]} fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M3 6a3 3 0 013-3h10a1 1 0 01.8 1.6L14.25 8l2.55 3.4A1 1 0 0116 13H6a1 1 0 00-1 1v3a1 1 0 11-2 0V6z" clip-rule="evenodd"></path>
                            </svg>
                          </div>
                          <div class="flex items-center space-x-1">
                            <span class="text-xs text-gray-500 dark:text-gray-400">Max CPU</span>
                            <span class="text-xs text-gray-900 dark:text-gray-100"><%= get_in(report, ["maximums", :cpu_percent]) || 0 %>%</span>
                            <svg class={["w-4 h-4", if(is_red_cpu_max?(report), do: "text-red-500 dark:text-red-400", else: "text-green-500 dark:text-green-400")]} fill="currentColor" viewBox="0 0 20 20">
                              <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"></path>
                            </svg>
                          </div>
                        </div>
                      </div>
                      <div class="flex items-center space-x-2">
                        <%= if get_in(report, ["result", "csv_url"]) do %>
                          <a
                            href={get_in(report, ["result", "csv_url"])}
                            target="_blank"
                            class="px-2 py-1 text-xs font-medium text-blue-600 bg-blue-50 rounded hover:bg-blue-100 dark:text-blue-400 dark:bg-blue-900 dark:hover:bg-blue-800"
                          >
                            CSV
                          </a>
                        <% end %>
                        <%= if get_in(report, ["result", "cw_url"]) do %>
                          <a
                            href={get_in(report, ["result", "cw_url"])}
                            target="_blank"
                            class="px-2 py-1 text-xs font-medium text-blue-600 bg-blue-50 rounded hover:bg-blue-100 dark:text-blue-400 dark:bg-blue-900 dark:hover:bg-blue-800"
                          >
                            CloudWatch
                          </a>
                        <% end %>
                        <button
                          class="px-2 py-1 text-xs font-medium text-red-600 bg-red-50 rounded hover:bg-red-100 dark:text-red-400 dark:bg-red-900 dark:hover:bg-red-800"
                          phx-click="remove_report"
                          phx-value-id={Map.get(report, "id")}
                        >
                          Clear
                        </button>
                      </div>
                    </div>
                  </div>
                <% end %>
              </div>
            <% else %>
              <p class="text-sm text-gray-500 dark:text-gray-400">No reports available</p>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Helper functions
  defp protocol_options do
    [
      {"http10", "HTTP 1.0"},
      {"http10s", "HTTP 1.0 over TLS"},
      {"http", "HTTP 1.1"},
      {"https", "HTTP 1.1 over TLS"},
      {"http2", "HTTP 2"},
      {"http2s", "HTTP 2 over TLS"},
      {"tcp", "TCP"},
      {"udp", "UDP"},
      {"script", "Custom Script"}
    ]
  end

  defp calculate_ramp_step_size(state) do
    generator_count = Map.get(state, "generator_count", 0)
    generator_count * 10
  end

  defp calculate_effective_size(state, desired_size_str) do
    case Integer.parse(desired_size_str) do
      {desired_size, ""} ->
        ramp_step_size = calculate_ramp_step_size(state)

        if ramp_step_size > 0 do
          ramp_steps = div(desired_size, ramp_step_size)
          max(ramp_steps * ramp_step_size, desired_size)
        else
          1
        end

      _ ->
        1
    end
  end

  defp format_stat_name(key) do
    suffix =
      cond do
        String.ends_with?(key, "_per_second") -> "(rate)"
        String.ends_with?(key, "_bytes_per_second") -> "(rate, bytes)"
        String.ends_with?(key, "_percent") -> "(%)"
        String.ends_with?(key, "_us") -> "(latency)"
        String.ends_with?(key, "_bytes_count") -> "(load, bytes)"
        String.ends_with?(key, "_count") -> "(count)"
        String.ends_with?(key, "_total") -> "(gauge)"
        true -> ""
      end

    base =
      key
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    if suffix == "", do: base, else: "#{base} #{suffix}"
  end

  defp format_stat_value(key, values) when is_list(values) do
    case List.first(values) do
      nil ->
        "-"

      value when is_number(value) ->
        cond do
          String.ends_with?(key, "_bytes_per_second") ->
            format_bytes(value) <> "/sec"

          String.ends_with?(key, "_per_second") ->
            format_number(value) <> " /sec"

          String.ends_with?(key, "_percent") ->
            "#{trunc(value)} %"

          String.ends_with?(key, "_us") ->
            format_time_us(value)

          String.ends_with?(key, "_bytes_count") ->
            format_bytes(value)

          String.ends_with?(key, "_count") ->
            format_number(value)

          String.ends_with?(key, "_total") ->
            format_number(value)

          true ->
            to_string(value)
        end

      value ->
        to_string(value)
    end
  end

  defp format_bytes(bytes) when bytes >= 1_000_000_000 do
    "#{Float.round(bytes / 1_000_000_000, 1)} GB"
  end

  defp format_bytes(bytes) when bytes >= 1_000_000 do
    "#{Float.round(bytes / 1_000_000, 1)} MB"
  end

  defp format_bytes(bytes) when bytes >= 1_000 do
    "#{Float.round(bytes / 1_000, 1)} KB"
  end

  defp format_bytes(bytes), do: "#{bytes} B"

  defp format_number(num) when num >= 1_000_000 do
    "#{Float.round(num / 1_000_000, 1)}M"
  end

  defp format_number(num) when num >= 1_000 do
    "#{Float.round(num / 1_000, 1)}K"
  end

  defp format_number(num), do: to_string(trunc(num))

  defp format_time_us(us) when us >= 1_000_000 do
    "#{trunc(us / 1_000_000)} seconds"
  end

  defp format_time_us(us) when us >= 1_000 do
    "#{trunc(us / 1_000)} milliseconds"
  end

  defp format_time_us(us), do: "#{us} microseconds"

  defp is_red_cpu?(values) when is_list(values) do
    case List.first(values) do
      value when is_number(value) -> value > 80
      _ -> false
    end
  end

  defp is_red_cpu_max?(report) do
    case get_in(report, ["maximums", :cpu_percent]) do
      value when is_number(value) -> value > 80
      _ -> false
    end
  end

  defp is_error_stat?(key) do
    key_str = to_string(key) |> String.downcase()

    String.ends_with?(key_str, "_error_count") or
    String.contains?(key_str, "error") or
    String.contains?(key_str, "fail") or
    String.contains?(key_str, "timeout")
  end

  defp has_errors?(report) do
    script_error = Map.get(report, "script_error")
    maximums = Map.get(report, "maximums", %{})
    error_keys = Enum.filter(Map.keys(maximums), &is_error_stat?/1)

    script_error != nil or length(error_keys) > 0
  end

  defp sparkline_data(values) do
    values
    |> Enum.reject(&is_nil/1)
    |> Enum.reverse()
    |> Enum.join(",")
  end

  defp get_metric_type(key) do
    IO.inspect({"key", key}, limit: :infinity, structs: false)
    key_str = to_string(key) |> String.downcase()

    cond do
      is_error_stat?(key) -> :error
      String.contains?(key_str, "_per_second") or String.contains?(key_str, "_bytes_per_second") -> :rate
      String.contains?(key_str, "_us") -> :latency
      String.contains?(key_str, "_count") or String.contains?(key_str, "_bytes_count") -> :count
      String.contains?(key_str, "_total") -> :total
      true -> :default
    end
  end

  defp get_metric_colors(type) do
    case type do
      :error -> "text-red-600 dark:text-red-300"
      :rate -> "text-blue-600 dark:text-blue-300"
      :latency -> "text-purple-600 dark:text-purple-300"
      :count -> "text-green-600 dark:text-green-300"
      :total -> "text-orange-600 dark:text-orange-300"
      :default -> "text-gray-700 dark:text-gray-100"
    end
  end

  defp get_value_colors(type) do
    case type do
      :error -> "text-red-600 dark:text-red-300"
      :rate -> "text-blue-600 dark:text-blue-300"
      :latency -> "text-purple-600 dark:text-purple-300"
      :count -> "text-green-600 dark:text-green-300"
      :total -> "text-orange-600 dark:text-orange-300"
      :default -> "text-gray-900 dark:text-gray-100"
    end
  end
end
