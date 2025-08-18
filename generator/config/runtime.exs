import Config

scripts_path = System.get_env("SCRIPTS_PATH") || "../scripts/config"

custom_scripts_config = Path.expand(Path.join(scripts_path, "runtime.exs"), __DIR__)

if File.exists?(custom_scripts_config) do
  Code.eval_file(custom_scripts_config)
end
