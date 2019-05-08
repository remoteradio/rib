defmodule Rib.Application do

  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do

    # A list of child processes to be supervised.  These are each
    # started as workers by calling the module's start_link.
    # for instance, {Rib.Worker, arg} Starts a worker by calling
    # Rib.Worker.start_link(arg)
    children = [
      # Tortoise (MQTT Client) Connection
      {Tortoise.Connection, 
        client_id: RIB,
        handler: {Tortoise.Handler.Logger, []},
        server: {Tortoise.Transport.Tcp, host: 'localhost', port: 1883},
        subscriptions: [{"rib/#", 0}]},
      # RIB Controller
      {Rib.Controller, []}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Rib.Supervisor]
    Supervisor.start_link(children, opts)
  end

end