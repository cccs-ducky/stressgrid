deps = [
  {:tesla, "~> 1.11"},
  {:finch, "~> 0.20"},
  {:websocket_client, "~> 1.5"}
]

supervisor_children = [
  PhoenixClient.ChannelSupervisor,
  {Finch,
   name: Stressgrid.Generator.Finch,
   pools: %{
     :default => [
       size: 40,
       count: System.schedulers_online(),
       conn_max_idle_time: 5_000,
       conn_opts: [
         transport_opts: [
           nodelay: true,
           keepalive: true
         ]
       ]
     ]
   }}
]
