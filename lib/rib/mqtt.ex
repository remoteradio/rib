defmodule Rib.MQTT.Handler do
  @moduledoc """
  This comes right out of the README for the Tortoise MQTT library.
  Almost no changes other than to cast messages for the rib to
  the controller.
  """

  require Logger
  use Tortoise.Handler

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
  def handle_message(["rib" | subtopics], payload, state) do
  	send(Rib.Controller, {:mqtt_message, subtopics, payload})
  	{:ok, state}
  end
  def handle_message(_topics, _payload, state) do  # ignore unmatched topics
    {:ok, state}
  end

  def subscription(_status, _topic_filter, state) do
    {:ok, state}
  end

  def terminate(_reason, _state) do
    :ok
  end
end