defmodule DAQC do

  @moduledoc """
  Support for pi-plates (DAQC board only, for now)

  ## Implementation Notes

  ### 1. API

  This Started as a more or less direct translation of ppDAQC.py, which is the
  Python "reference" implementation. As I  went along, I decided to move to more
  to elixir-y idioms, so the API is now quite a bit different.

  I decided to store "global" references in ets, and eliminate passing a ref
  to each function, making all functions effectively global. I realize this will
  be controversial for savvy elixir/erlang readers, however this makes the
  library more approachable to beginners, and in fact, there can only ever be one
  instance of pi-plates running in any running vm anyway, due to the way that
  pi-plates manages SPI I/O.

  ### 2. Stability and Delay for SPI

  Initially the low level i/o copied the python ppCMD() logic directly, but
  the elixir verions of getADCall() and getID() functions were unstable or
  returned wrong results. Upon investigation, the python ones did also!!

  The python getID() function doesn't seem to work reliably on a PI 3B+ nor
  does the getADCall(). The elixir versions of these functions now work
  properly, by inserting a small delay (1ms) between each byte read (not
  just at the beginning of reading a response). This has resulted in proper
  and reliable operation.

  Note that the python implementation seems to specify a 100us sleep before
  reading a value, however, in python a sleep() relinquishes the cpu to the
  OS anyway, which results in a minimum OS scheduler latency of about
  3-10ms in linux, whereas his only releases the CPU to the erlang VM,
  which will hold fairly tightly to 1ms, so the Elixir implementation
  should usually result in lower overall latency than the python version.
  In addition, the requirement for these delays will block the entire
  python interpreter, due to the GIL. In Elixir, this only blocks the
  process actually interacting with the pi-plate, allowing building
  reliable and performant systems.
"""

  require Logger

  # allow ease of referencing Circuits.GPIO.whatever(), as just GPIO.whatever()

  alias Circuits.SPI
  alias Circuits.GPIO


  @doc """
  Initalizes the board

  Sets up the "global I/O context" in ETS so it can be retreived by get_io()
  Initializes basic features of the board.
  """
  @spec init() :: :ok | {:error, :already_initialized}

  # GPIO pin for SPI frame select
  @ppFRAME 25
  # GPIO pin for Interrupt
  @ppINT 22
  # SPI channel used
  @ppSPI "spidev0.1"

  @type channel :: integer

  @type addr :: integer

  def init do
    case :ets.info(:pi_plates) do
      :undefined ->
        :ets.new(:pi_plates, [:named_table])
        :ets.insert(:pi_plates, {:io, init_spi_and_gpio()})
        # NYI - init_all_boards()
        :ok
      _ ->
        {:error, :already_initialized}
    end
  end

  # create a "global I/O" context, which is stored in ETS by init()
  defp init_spi_and_gpio do
    {:ok, gpio_frame} = GPIO.open(@ppFRAME, :output, [{:initial_value, 0}])
    {:ok, gpio_int} = GPIO.open(@ppINT, :input, [{:pull_mode, :pullup}])
    {:ok, spi_ref} = SPI.open(@ppSPI)

    %{
      gpio_frame: gpio_frame,
      gpio_int: gpio_int,
      spi: spi_ref
    }
  end

  @doc "Return the global I/O references (which are setup by init())"
  @spec io_context() :: map
  def io_context do
    case :ets.lookup(:pi_plates, :io) do
      [{:io, value}] -> value
      _ -> raise "DAQC i/o not yet initialized - please call init() first"
    end
  end

  defmodule Raw do
    @moduledoc "Raw I/O functions to talk to DAQC board's microcontroller"

    @gpio_base_addr 8
    # 1ms delay before each DAQC uController read
    @daqc_read_delay 1

    @type addr :: DAQC.addr

    @doc "Sends command to the board, without expecting response"
    @spec cmd(addr, integer, integer, integer) :: :ok
    def cmd(addr, cmd, param1, param2 \\ 0) when addr <= 7 do
      io = DAQC.io_context()
      GPIO.write(io.gpio_frame, 1)
      :timer.sleep 1   # experiment to solve write instability
      {:ok, _} = SPI.transfer(io.spi, <<addr + @gpio_base_addr, cmd, param1, param2>>)
      :timer.sleep 1   # experiment to solve write instability
      GPIO.write(io.gpio_frame, 0)
      :ok
    end

    @doc "Sends query command, returns a binary response of <len> bytes"
    @spec query(addr, integer, integer, integer, integer) :: binary
    def query(addr, cmd, param1, param2, len) when addr <= 7 and len > 0 do
      io = DAQC.io_context()
      GPIO.write(io.gpio_frame, 1)
      :timer.sleep 1   # experiment to solve read instability on single-byte reads
      {:ok, _} = SPI.transfer(io.spi, <<addr + @gpio_base_addr, cmd, param1, param2>>)
      :timer.sleep 1   # experiment to solve read instability on single-byte reads
      response =
        0..(len - 1)
        |> Enum.map(fn _ -> spi_read_single_byte(io.spi) end)
        |> :erlang.list_to_binary()
      GPIO.write(io.gpio_frame, 0)
      response
    end

    # read an SPI byte - see implementation notes in file for timer rationale
    defp spi_read_single_byte(spi) do
      :timer.sleep(@daqc_read_delay)
      {:ok, <<byte>>} = SPI.transfer(spi, <<0x00>>)
      byte
    end
  end

  defmodule Board do
    @moduledoc "Functions relating to enumerating and identifying DAQC boards"

    @doc "Return a list of addresses where DAQC boards are present"
    @spec address_list() :: list(DAQC.addr)
    def address_list do
      Enum.reject(0..7, &(!present?(&1)))
    end

    @doc "Returns true if a DAQC board exists on the specified address"
    @spec present?(integer) :: boolean
    def present?(addr) do
      read_raw_address(addr) == (addr + 8)
    end

    @doc "Return the string identifier for this board"
    @spec id(DAQC.addr) :: String.t
    def id(addr) do
      Raw.query(addr, 0x01, 0, 0, 20)
      |> String.trim(<<0x00>>)
    end

    @doc "Gets the raw address for a board (should be addr+8)"
    @spec read_raw_address(DAQC.addr) :: integer
    def read_raw_address(addr) do
      <<raw_address>> = Raw.query(addr, 0x00, 0, 0, 1)
      raw_address
    end
  end

  defmodule DAC do
    @moduledoc """
    Functions to deal with DAC as raw (uncalibrated) integer values, that apply to both PWM
    and DAC.   It looks like the formula to convert to volts is:

    - volts = (Vcc * value) / 1024
    - value = (volts / vcc) * 1024
    """

    def write(addr, channel, value) when channel == 0 or channel == 1 do
      <<hibyte, lowbyte>> = <<value :: 16>>
      Raw.cmd(addr, 0x40+channel, hibyte, lowbyte)
    end

    def read(addr, channel) when channel == 0 or channel == 1 do
      <<value :: 16>> = Raw.query(addr, 0x42+channel, 0, 0, 2)
      value
    end
  end

  defmodule ADC do
    @moduledoc "Functions related to ADC input"

    @doc "Returns voltage from a single ADC channel(0-7)"
    @spec read(DAQC.addr, DAQC.channel) :: float
    def read(addr, channel) when is_integer(channel) and channel <= 7 do
      read_scaled(addr, channel)
    end

    @doc "Return the system voltage for the DAQC"
    @spec read_vin(DAQC.addr) :: float
    def read_vin(addr) do
      2 * read_scaled(addr, 8)
    end

    @doc "Returns a list of the voltages from ADC channels 0-7"
    @spec read_all(DAQC.addr) :: [float]
    def read_all(addr) do
      <<a::16, b::16, c::16, d::16, e::16, f::16, g::16, h::16>> =
        Raw.query(addr, 0x31, 0, 0, 16)
      [a, b, c, d, e, f, g, h]
      |> Enum.map(&Float.round(&1 * 4.096 / 1024, 3))
    end

    @spec read_scaled(DAQC.addr, DAQC.channel) :: float
    defp read_scaled(addr, channel) do
      <<value::16>> = Raw.query(addr, 0x30, channel, 0, 2)
      Float.round(value * 4.096 / 1024, 3)
    end
  end

  defmodule LED do
    @moduledoc "Manage the bi-color LED on the board (color 0=red, 1=green)"
    @type addr :: DAQC.addr
    @type color :: :off | :red | :green | :yellow

    # define a constant map of color atoms to tuples, so :red maps to {1,0}
    # also define an inverse version, where {1,0} maps to :red, for instance
    @color_map %{off: {0,0}, red: {1,0}, green: {0,1}, yellow: {1,1}}
    @inverse_color_map (for {k, v} <- @color_map, into: %{}, do: {v, k})

    @doc """
    Set the color of the LED for <addr> to correspond to color atom
    (:off, :red, :green, :yellow)
    """
    @spec set_color(addr, color) :: :ok
    def set_color(addr, color) do
      case @color_map[color] do
        {r, g} ->
          set_individual_led(addr, 0, r)   # write red state
          set_individual_led(addr, 1, g)   # write green state
        _ ->  # color not found in map
          Logger.error "Invalid color atom passed to DAQC.LED.set_color()"
      end
      :ok
    end

    @doc """
    Return the color atom (:off, :red, :green, :yellow) corresponding to the bicolor LEDs
    current state.
    """
    @spec get_color(addr) :: color
    def get_color(addr) do
      <<r>> = Raw.query(addr, 0x63, 0, 0, 1) # read red state
      <<g>> = Raw.query(addr, 0x63, 1, 0, 1) # read green state
      @inverse_color_map[{r,g}]              # e.g. convert {0,1} to :green
    end

    # Private Helpers

    # set or clear the state of the individual LEDs (0=red or 1=green) that make up the bicolor LED
    defp set_individual_led(addr, bicolor_id, value) when value == 1 do
      Raw.cmd(addr, 0x60, bicolor_id, 0)
    end
    defp set_individual_led(addr, bicolor_id, value) when value == 0 do
      Raw.cmd(addr, 0x61, bicolor_id, 0)
    end

  end

  defmodule DIN do
    @moduledoc "Digital input (DIN) functions"

    @type addr :: DAQC.addr
    @type bit :: integer
    @type value :: 0 | 1

    # define guard to ensure DIN bit is valid integer from 0-7
    defmacrop is_bit(b) do
      quote do: (is_integer(unquote(b)) and unquote(b) >= 0 and unquote(b) <= 7)
    end

    @doc "Read a single digital input"
    @spec read(addr, bit) :: value
    def read(addr, bit) when is_bit(bit) do
      <<byte>> = Raw.query(addr, 0x20, bit, 0, 1)
      byte
    end

    @doc "Reads all 8 digital input values as a single byte"
    @spec read_all(addr) :: integer
    def read_all(addr) do
      <<byte>> = Raw.query(addr, 0x25, 0, 0, 1)
      byte
    end
  end

  defmodule DOUT do
    @moduledoc "Digital output (DOUT) functions"

    @type addr :: DAQC.addr
    @type bit :: integer
    @type value :: 0 | 1

    # define guard to ensure DOUT bit is valid integer from 0-6
    defmacrop is_bit(b) do
      quote do: (is_integer(unquote(b)) and unquote(b) >= 0 and unquote(b) <= 6)
    end

    @doc "Sets (turns on) a digital output bit"
    @spec set(addr, bit) :: :ok
    def set(addr, bit) when is_bit(bit) do
      Raw.cmd(addr, 0x10, bit)
    end

    @doc "Clears (turns off) a digital output bit"
    @spec clear(addr, bit) :: :ok
    def clear(addr, bit) when is_bit(bit) do
      Raw.cmd(addr, 0x11, bit)
    end

    @doc "Toggles a digital output bit"
    @spec toggle(addr, bit) :: :ok
    def toggle(addr, bit) when is_bit(bit) do
      Raw.cmd(addr, 0x12, bit)
    end

    @doc "Writes a bit value (0 or 1) to a digital output bit"
    @spec write(addr, bit, value) :: :ok
    def write(addr, bit, value) when value == 1 do
      set(addr, bit)
    end
    def write(addr, bit, value) when value == 0 do
      clear(addr, bit)
    end

    @doc "Reads the state of all bits at once as a byte"
    @spec read_all(addr) :: integer
    def read_all(addr) do
      <<byte>> = Raw.query(addr, 0x14, 0, 0, 1)
      byte
    end

    @doc "Writes a byte to set the state of all bits at once"
    @spec write_all(addr, integer) :: :ok
    def write_all(addr, byte) when byte < 128 do
      Raw.cmd(addr, 0x13, byte)
    end
  end

end

