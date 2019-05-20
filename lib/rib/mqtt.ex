defmodule Rib.MQTT.Handler do
  @moduledoc """
  This comes right out of the README for the Tortoise MQTT library.
  Almost no changes other than to cast messages for the rib to
  the controller.
  """

  use Tortoise.Handler

  def start_supervision() do
    Tortoise.Supervisor.start_child(
      client_id: RIB,
      handler: {Tortoise.Handler.Logger, []},
      server: {Tortoise.Transport.Tcp, host: 'localhost', port: 1883},
      subscriptions: [{"rib/#", 0}])
  end

  def init(args) do
    {:ok, args}
  end

  def connection(_status, state) do
    # `status` will be either `:up` or `:down`; you can use this to
    # inform the rest of your system if the connection is currently
    # open or closed; tortoise should be busy reconnecting if you get
    # a `:down`
    {:ok, state}
  end

  # send all messages matching rib/# to the controller, ignore all
  # others to avoid unknown messages from crashing due to no match
  def handle_message(["rib" | subtopic], payload, state) do
  	send(Rib.Controller, {:mqtt_message, subtopic, payload})
  	{:ok, state}
  end
  def handle_message(_topic, _payload, state) do  # default case - ignore msg
    {:ok, state}
  end

  def subscription(_status, _topic_filter, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end