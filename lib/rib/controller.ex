defmodule Rib.Controller do

  use GenServer

  # a map of DAQC state field keys to MQTT topics
  @daqc_topics %{
    adc_vin:    "adc/vin",
    din_all:    "din/all",
    dout_all:   "dout/all",
    adc0: "adc/0", adc1: "adc/1", adc2: "adc/2", adc3: "adc/3",
    adc4: "adc/4", adc5: "adc/5", adc6: "adc/6", adc7: "adc/7"
  }

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def init(_args) do
    :ok = DAQC.init()
    Tortoise.publish RIB, "rib/controller/time_last_started", timestamp(), retain: true
    Tortoise.publish RIB, "rib/daqc/id", DAQC.Board.id(0), retain: true
    Tortoise.publish RIB, "rib/daqc/address_list", DAQC.Board.address_list(), retain: true

    # send the first messagesto kick off 100ms and 1000ms repetitve ticks
    send self(), :tick_1000
    send self(), :tick_100

    initial_state = %{daqc: %{}}
    {:ok, initial_state}
  end

  # invoked every 1000ms when we receive the :tick_1000 message
  def handle_info(:tick_1000, state) do
    Tortoise.publish RIB, "rib/controller/time_last_updated", timestamp(), retain: true
    Process.send_after self(), :tick_1000, 1000    # schedule another tick in another 1000ms
    {:noreply, state}
  end

  # invoked every 100ms when we receive the :tick_100 message
  # walk through all topics in the daqc_topics map, and only publish changes to the ones
  # REVIEW replace inspect(..) below with a better way of converting to string payload
  def handle_info(:tick_100, state) do
    new_daqc = read_daqc(0)
    Enum.each @daqc_topics, fn {key, subtopic} -> 
      if (state.daqc[key] != new_daqc[key]) do
        Tortoise.publish RIB, "rib/controller/#{subtopic}", inspect(new_daqc[key])
      end
    end
    Process.send_after self(), :tick_100, 100    # schedule another tick in another 100ms
    {:noreply, %{state | daqc: new_daqc}}
  end

  # Return a map with values that reflect the current DAQC state for each key
  defp read_daqc(address) do
    [a0, a1, a2, a3, a4, a5, a6, a7] = DAQC.ADC.read_all(address)
    %{
      adc_vin:   DAQC.ADC.read_vin(address),
      din_all:    DAQC.DIN.read_all(address),
      dout_all:   DAQC.DOUT.read_all(address),
      adc0: a0, adc1: a1, adc2: a2, adc3: a3, adc4: a4, adc5: a5, adc6: a6, adc7: a7
    }
  end

  # helper function to return a ISO 8601 formatted time string
  defp timestamp do
    DateTime.to_iso8601(DateTime.utc_now())
  end

end