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
    addr = DAQC.Board.address_list()
    Tortoise.publish RIB, "rib/controller/time_last_started", timestamp(), retain: true
    Enum.each(addr, fn address -> Tortoise.publish RIB, "rib/daqc/#{address}/id", DAQC.Board.id(address), retain: true end)

    # send the first messages to kick off 100ms, 1000ms, and 5000ms repetitve ticks
    send self(), :tick_500        # must be sent first to force read and init state.daqc hash
    send self(), :tick_1000
    send self(), :tick_5000

    initial_state = Map.merge(%{addr: addr}, (Enum.reduce addr, %{}, fn x, acc -> Map.put(acc, x, %{}) end))
    {:ok, initial_state}
  end

  # GENERAL MESSAGE HANDLERS

  # invoked when we get an MQTT messages -- delegates to handle_mqtt function for clarity
  def handle_info({:mqtt_message, subtopic, payload}, state) do
    handle_mqtt(subtopic, payload, state)
  end

  # invoked every 500ms when we receive the :tick_500 message
  # walk through all topics in the daqc_topics map, and only publish changes to the ones
  # REVIEW replace inspect(..) below with a better way of converting to string payload
  def handle_info(:tick_500, state) do
    Tortoise.publish RIB, "rib/controller/time_last_updated", timestamp(), retain: true
    new_state = Enum.reduce(state.addr, state, fn x, acc -> publish_daqc_delta(x, acc) end)
    Process.send_after self(), :tick_500, 500    # schedule another tick in another 100ms
    {:noreply, new_state}
  end

  # invoked every 1000ms when we receive the :tick_1000 message
  def handle_info(:tick_1000, state) do
    Enum.each state.addr, fn address ->
      Tortoise.publish RIB, "rib/daqc/#{address}/led/color", Atom.to_string(DAQC.LED.get_color(address))
      for channel <- 0..1 do
        publish_dac_values(address, channel, state)
        publish_dac_values(address, channel, state)
      end
    end
    Process.send_after self(), :tick_1000, 1000    # schedule another tick in another 1000ms
    {:noreply, state}
  end

  # invoked every 5000ms when we receive the :tick_5000 message
  def handle_info(:tick_5000, state) do
    # get the temperature of the SoC core and format as a rounded float and then publish
    # only do this if the /sys/class/thermal filesystem exists (not on macOS)
    case File.read "/sys/class/thermal/thermal_zone0/temp" do
      {:ok, core_temp} ->
        {core_temp, _} = Integer.parse(core_temp)
        core_temp = Kernel.round(core_temp / 1000.0)
        core_temp = Integer.to_string(core_temp) <> "C"
        Tortoise.publish RIB, "rib/controller/SoC_core_temp", core_temp, retain: true
      _ -> nil
    end
    Process.send_after self(), :tick_5000, 5000    # schedule another tick in another 5000ms
    {:noreply, state}
  end

  # MQTT HANDLERS
  #
  # These are invoked to handle incoming messages on specific MQTT topics.
  # Each function clause matches one or more subscriptions.
  #
  # For now, these assume board 0.

  def handle_mqtt(["daqc", address, "led", "color", "set"], payload, state) do
    DAQC.LED.set_color(String.to_integer(address), String.to_atom(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", address, "dac", channel, "raw", "set"], payload, state) do
    DAQC.DAC.write(String.to_integer(address), String.to_integer(channel), String.to_integer(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", address, "dac", channel, "set"], payload, state) do
    case Float.parse(payload) do
      {volts, _rest} ->
        dac_value = (volts / state[String.to_integer(address)][:adc_vin]) * 1024
        DAQC.DAC.write(String.to_integer(address), String.to_integer(channel), floor(dac_value))
      :error ->
        Logger.warn "Invalid DAC voltage requested: #{payload}"
    end
    {:noreply, state}
  end
  def handle_mqtt(["daqc", address, "dout", "all", "set"], payload, state) do
    Logger.info "Got daqc/dout/all/set with payload #{payload}"
    DAQC.DOUT.write_all(String.to_integer(address), String.to_integer(payload))
    {:noreply, state}
  end
  def handle_mqtt(["daqc", address, "dout", bit, "set"], payload, state) do
    Logger.info "Got daqc/dout/#{bit}/set with payload #{payload}"
    DAQC.DOUT.write(String.to_integer(address), String.to_integer(bit), String.to_integer(payload))
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
  defp publish_daqc_delta(address, state) do
    new_daqc = read_daqc(address)
    Enum.each @daqc_topics, fn {key, subtopic} ->
      if (state[address][key] != new_daqc[key]) do
        Tortoise.publish RIB, "rib/daqc/#{address}/#{subtopic}", inspect(new_daqc[key])
      end
    end
    %{state | address => new_daqc}
  end

  defp publish_dac_values(address, channel, state) do
    raw_value = DAQC.DAC.read(address, channel)
    volts = (raw_value * state[address][:adc_vin]) / 1024
    Tortoise.publish RIB, "rib/daqc/#{address}/dac/#{channel}/raw", Integer.to_string(raw_value)
    Tortoise.publish RIB, "rib/daqc/#{address}/dac/#{channel}", Float.to_string(volts)
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
