defmodule Rib.Controller do

  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = DAQC.init()
    Tortoise.publish RIB, "rib/controller/last_started", timestamp(), retain: true
    schedule_next_tick()
    {:ok, nil}
  end

  # invoked when we get the :tick message sent to this process
  def handle_info(:tick, state) do
    update_topics
    schedule_next_tick()
    {:noreply, state}
  end

  # set a timer to send this process (self) a :tick message in one second
  defp schedule_next_tick do
    Process.send_after(self(), :tick, 1000)
  end

  # invoked by handle_info(:tick...) each second
  defp update_topics do
    Tortoise.publish RIB, "rib/controller/last_update", timestamp(), retain: true
    Tortoise.publish RIB, "rib/daqc/din", DAQC.DIN.read_all(0), retain: true
    Tortoise.publish RIB, "rib/daqc/dout", DAQC.DOUT.read_all(0), retain: true
    Enum.each (0..3), fn(n) ->
      Tortoise.publish(RIB, "rib/daqc/adc/#{n}",
                       Float.to_string(DAQC.ADC.read(0,n)), retain: true)
    end
  end

  # helper function to return a ISO 8601 formatted time string
  defp timestamp do
    DateTime.to_iso8601(DateTime.utc_now())
  end

end