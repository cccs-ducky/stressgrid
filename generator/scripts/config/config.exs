import Config

config :tesla, :adapter, {
  Tesla.Adapter.Finch,
  name: Stressgrid.Generator.Finch
}

config :tesla, disable_deprecated_builder_warning: true

import_config "#{Mix.env()}.exs"
