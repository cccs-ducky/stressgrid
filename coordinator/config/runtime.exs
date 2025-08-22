import Config

# load environment variables from .env file if it exists
if File.exists?(".env") do
  Dotenv.load!()
end

config :logger,
  level: System.get_env("LOGGER_LEVEL", "info") |> String.to_atom()

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/coordinator start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :coordinator, Stressgrid.CoordinatorWeb.Endpoint, server: true
end

config :coordinator, :telemetry,
  statsd_prefix: System.get_env("STATSD_PREFIX") || "stressgrid",
  statsd_host: System.get_env("STATSD_HOST") || "localhost",
  # 1432 - default udp datagram size for statsd datadog native clients
  # https://github.com/DataDog/datadog-go/blob/3255e6186e83fad1e447573c9fa03dd13c023394/statsd/statsd.go#L35-L41
  mtu: String.to_integer(System.get_env("COORDINATOR_TELEMETRY_MTU", "1432")),
  buffer_flush_ms:
    String.to_integer(System.get_env("COORDINATOR_TELEMETRY_BUFFER_FLUSH_MS", "1000")),
  pool_size:
    String.to_integer(
      System.get_env("COORDINATOR_TELEMETRY_POOL_SIZE", "#{System.schedulers_online()}")
    )

config :coordinator,
  generators_port: String.to_integer(System.get_env("GENERATORS_PORT", "9696")),
  management_port: String.to_integer(System.get_env("MANAGEMENT_PORT", "8000")),
  report_interval_seconds: String.to_integer(System.get_env("REPORT_INTERVAL_SECONDS", "60")),
  report_writers:
    System.get_env("REPORT_WRITERS", "csv,cloudwatch,statsd")
    |> String.split(",")
    |> Enum.map(&String.trim/1),
  cooldown_ms: String.to_integer(System.get_env("COOLDOWN_MS", "10000")),
  notify_interval_ms: String.to_integer(System.get_env("NOTIFY_INTERVAL_MS", "1000"))

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :coordinator, Stressgrid.CoordinatorWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :coordinator, Stressgrid.CoordinatorWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :coordinator, Stressgrid.CoordinatorWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
