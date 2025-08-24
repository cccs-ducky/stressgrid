defmodule Stressgrid.Generator.Scripts.HttpRequestDemo do
  use Stressgrid.Generator.ScriptGenServer

  require Logger

  import Stressgrid.Generator.DeviceContext

  defmodule ExampleDotComClient do
    use Tesla

    plug(Tesla.Middleware.BaseUrl, "https://example.com")
    plug(Tesla.Middleware.Timeout, timeout: 1000)
  end

  def do_init(state) do
    {:ok, state}
  end

  def run(state) do
    start_timing(:request)

    result = ExampleDotComClient.get("/")

    stop_timing(:request)

    case result do
      {:ok, %Tesla.Env{status: status}} ->
        inc_counter(:http_requests, 1)

        inc_counter(:"http_status_#{status}", 1)

      {:error, reason} ->
        inc_counter(:http_errors, 1)

        Logger.error("HTTP request failed: #{inspect(reason)}")
    end

    {:stop, :shutdown, state}
  end
end
