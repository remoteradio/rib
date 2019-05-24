defmodule Rib.Controller do

  require Logger
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
    Tortoise.publish RIB, "rib/daqc/address_list", inspect(DAQC.Board.address_list()), retain: true

    # send the first messages to kick off 100ms, 1000ms, and 5000ms repetitve ticks
    send self(), :tick_100        # must be sent first to force read and init state.daqc hash
    send self(), :tick_1000
    send self(), :tick_5000

    initial_state = %{daqc: %{}}
    {:ok, initial_state}
  end

  # GENERAL MESSAGE HANDLERS

  # invoked when we get an MQTT messages -- delegates to handle_mqtt function for clarity
  def handle_info({:mqtt_message, subtopic, payload}, state) do
    handle_mqtt(subtopic, payload, state)
  end

  # invoked every 5000ms when we receive the :tick_5000 message
  def handle_info(:tick_5000, state) do
    # get the temperature of the SoC core and format as a rounded float and then publish
    # only do this if the /sys/class/thermal filesystem exists (not on macOS)
    case File.read "/sys/class/thermal/thermal_zone0/temp" do
      {:ok, coreTemp} ->
        {coreTemp, _} = Integer.parse(coreTemp)
        coreTemp = Float.round(coreTemp / 1000.0, 1)
        coreTemp = Float.to_string(coreTemp)
        Tortoise.publish RIB, "rib/controller/SoC_core_temp", coreTemp, retain: true
      _ -> nil
    end
    Process.send_after self(), :tick_5000, 5000    # schedule another tick in another 5000ms
    {:noreply, state}
  end

  # invoked every 1000ms when we receive the :tick_1000 message
  def handle_info(:tick_1000, state) do
    Tortoise.publish RIB, "rib/controller/time_last_updated", timestamp(), retain: true
    Tortoise.publish RIB, "rib/daqc/led/color", Atom.to_string(DAQC.LED.get_color(0))
    publish_dac_values(0, state)
    publish_dac_values(1, state)
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
        Tortoise.publish RIB, "rib/daqc/#{subtopic}", inspect(new_daqc[key])
      end
    end
    Process.send_after self(), :tick_100, 100    # schedule another tick in another 100ms
    {:noreply, %{state | daqc: new_daqc}}
  end

  # MQTT HANDLERS
  #
  # These are invoked to handle incoming messages on specific MQTT topics.
  # Each function clause matches one or more subscriptions.
  #
  # For now, these assume board 0.

  def handle_mqtt(["daqc", "led", "color", "set"], payload, state) do
    DAQC.LED.set_color(0, String.to_atom(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", "dac", channel, "raw", "set"], payload, state) do
    DAQC.DAC.write(0, String.to_integer(channel), String.to_integer(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", "dac", channel, "set"], payload, state) do
    case Float.parse(payload) do
      {volts, _rest} ->
        dac_value = (volts / state.daqc[:adc_vin]) * 1024
        DAQC.DAC.write(0, String.to_integer(channel), floor(dac_value))
      :error ->
        Logger.warn "Invalid DAC voltage requested: #{payload}"
    end
    {:noreply, state}
  end
  def handle_mqtt(["daqc", "dout", "all", "set"], payload, state) do
    Logger.info "Got daqc/dout/all/set with payload #{payload}"
    DAQC.DOUT.write_all(0, String.to_integer(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", "dout", bit, "set"], payload, state) do
    Logger.info "Got daqc/dout/#{bit}/set with payload #{payload}"
    DAQC.DOUT.write(0, String.to_integer(bit), String.to_integer(payload))
    {:noreply, state}
  end
  def handle_mqtt(["test", "logme"], payload, state) do
    Logger.info "Got rib/test/logme with payload #{payload}"
    {:noreply, state}
  end
  def handle_mqtt(_subtopic, _payload, state) do    # default is just to ignore the message
    {:noreply, state}
  end

  # PRIVATE HELPERS

  # reads the DAC value from hardware (should be what last written), publishes
  # both this raw value (at daqc/dac/<channel>/raw) and the computed voltage
  # (at daqc/dac/<channel>).   Needs to be passed the state so we can calibarate
  # the DAC values against the current Vcc (which is in state.daqc[:adc_vin])
  defp publish_dac_values(channel, state) do
    raw_value = DAQC.DAC.read(0, channel)
    volts = (raw_value * state.daqc[:adc_vin]) / 1024
    Tortoise.publish RIB, "rib/daqc/dac/#{channel}/raw", Integer.to_string(raw_value)
    Tortoise.publish RIB, "rib/daqc/dac/#{channel}", Float.to_string(volts)
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
