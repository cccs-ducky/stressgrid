import Config

import_config "#{Mix.env()}.exs"

scripts_path = System.get_env("SCRIPTS_PATH") || "../scripts/config"

custom_scripts_config = Path.expand(Path.join(scripts_path, "config.exs"), __DIR__)

if File.exists?(custom_scripts_config) do
  import_config custom_scripts_config
end
