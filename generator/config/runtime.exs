import Config

# load environment variables from .env file if it exists
if File.exists?(".env") do
  Dotenv.load!()
end

config :logger,
  level: System.get_env("LOGGER_LEVEL", "info") |> String.to_atom()

default_generator_id = fn ->
  host = :inet.gethostname() |> elem(1) |> to_string()

  uniq = :rand.uniform(1_000_000_000)

  "#{host}-#{uniq}"
end

config :generator,
  generator_id: System.get_env("GENERATOR_ID", default_generator_id.()),
  coordinator_url: System.get_env("COORDINATOR_URL", "ws://localhost:9696"),
  network_device: System.get_env("NETWORK_DEVICE")

scripts_path = System.get_env("SCRIPTS_PATH") || "../scripts/config"

custom_scripts_config = Path.expand(Path.join(scripts_path, "runtime.exs"), __DIR__)

if File.exists?(custom_scripts_config) do
  Code.eval_file(custom_scripts_config)
end
