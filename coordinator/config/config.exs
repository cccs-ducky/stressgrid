import Config

config :coordinator,
  namespace: Stressgrid.Coordinator,
  generators: [timestamp_type: :utc_datetime]

# Configures the endpoint
config :coordinator, Stressgrid.CoordinatorWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [
      html: Stressgrid.CoordinatorWeb.ErrorHTML,
      json: Stressgrid.CoordinatorWeb.ErrorJSON
    ],
    layout: false
  ],
  pubsub_server: Stressgrid.Coordinator.PubSub,
  live_view: [signing_salt: "+kQm8/k7"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.17.11",
  coordinator: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  coordinator: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :ex_aws,
  json_codec: Jason

import_config "#{Mix.env()}.exs"
