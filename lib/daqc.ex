defmodule DACQ do

    @moduledoc """
    Support for pi-plates (DACQ board only, for now)

    ## Implementation Notes

    1.  Started as a more or less direct translation of ppDAQC.py, which is the Python
        "reference" implementation.   As I went along, I decided to move to more
        to elixir-y idioms, so the API is now quite a bit different.

    2.  Initially the low level i/o copied the python ppCMD() logic directly, but the
        elixir verions of getADCall() and getID() functions were unstable or returned wrong results.
        Upon investigation, the python ones did also.   The python getID() function
        doesn't seem to work reliably on a PI 3B+ nor does the getADCall().  The
        elixir versions of these functions now work properly, by inserting a small
        delay (1ms) between each byte read (not just at the beginning of reading a
        response).   This has resulted in proper and reliable operation.

        Note that the python implementation seems to specify a 100us sleep before
        reading a value, however, in python a sleep() relinquishes the cpu to the
        OS anyway, which results in a minimum OS scheduler latency of about
        3-10ms in linux, whereas his only releases the CPU to the erlang VM,
        which will hold fairly tightly to 1ms, so the Elixir implementation should
        usually result in lower overall latency than the python version.   In addition,
        the requirement for these delays will block the entire python interpreter,
        due to the GIL.   In Elixir, this only blocks the process actually
        interacting with the pi-plate, allowing building reliable and performant
        systems.

    3.  I decided to store "global" references in ets, and eliminate passing a ref
        to each function, making all functions effectively global.   I realize this will
        be controversial for savvy elixir/erlang readers, however this makes the library
        more approachable to beginners, and in fact, there can only ever be one
        instance of pi-plates running in any running vm anyway, due to the way that
        pi-plates manages SPI I/O.
    """

    # allow ease of referencing Circuits.GPIO.whatever(), as just GPIO.whatever()

    alias Circuits.SPI
    alias Circuits.GPIO

    @dacq_read_delay    1           # 1ms delay before each DACQ uController read

    @doc """
    Initalizes the board

    Sets up the "global I/O context" in ETS so it can be retreived by get_io()
    Initializes basic features of the board.
    """
    @spec init() :: :ok | {:error, :already_initialized}

    @ppFRAME        25                      # GPIO pin for SPI frame select
    @ppINT          22                      # GPIO pin for Interrupt
    @ppSPI          "spidev0.1"             # SPI channel used

    def init do
        case :ets.info(:pi_plates) do
            :undefined ->
              :ets.new(:pi_plates, [:named_table])
              :ets.insert(:pi_plates, {:io, init_spi_and_gpio()})
              :ok
            _ ->
              {:error, :already_initialized}
        end
    end

    # create a "global I/O" context, which is stored in ETS by init()
    defp init_spi_and_gpio do
        {:ok, gpio_frame} = GPIO.open(@ppFRAME, :output)
        {:ok, gpio_int} = GPIO.open(@ppINT, :input)
        :ok = GPIO.set_pull_mode(gpio_int, :pullup)
        {:ok, spi_ref} = SPI.open(@ppSPI)
        %{
            gpio_frame: gpio_frame,
            gpio_int: gpio_int,
            spi: spi_ref
        }
    end

    @doc "Return the global I/O context (setup by init())"
    def get_io() do
        case :ets.lookup(:pi_plates, :io) do
            [{:io, value}] -> value
            _ -> raise "I/O not yet initialized - call init()"
        end
    end

    @doc "Return a list of addresses where DACQ boards are present"
    def list() do
        Enum.reject(0..7, &(! present?(&1)))
    end

    @doc "Predicate for presense of a board on specified address"
    @spec present?(integer) :: bool
    def present?(addr) do
        proper_response = <<(addr+8)>>
        case getADDR(addr) do
            ^proper_response -> true
            _ -> false
        end
    end

    @doc "Return the string identifier for this board"
    def board_id(addr) do
        ppCMD(addr, 0x01, 0, 0, 20)
        |> String.trim(<<0x00>>)
    end


    @doc "Read from the ADC (channel 8 is double scaled for some reason)"
    def adc_read(addr, channel) when channel <= 7 do
        adc_read_scaled(addr, channel)
    end
    def adc_read(addr, channel) when channel == 8 do
        2 * adc_read_scaled(addr, channel)
    end

    defp adc_read_scaled(addr, channel) do
        <<value::16>> = ppCMD(addr, 0x30, channel, 0, 2)
        Float.round(value * 4.096/1024, 3)
    end

    @doc "Read all ADC as list"
    # REVIEW - this does not return or scale channel 8
    def adc_read_all(addr) do
        bytes = ppCMD(addr, 0x31, 0, 0, 16)
        <<a::16,b::16,c::16,d::16,e::16,f::16,g::16,h::16>> = bytes
        [a,b,c,d,e,f,g,h]
        |> Enum.map(&(Float.round(&1 * 4.096/1024, 3)))
    end


    # defp ensure_analog_params(channel, value) do
    #     cond do
    #         value < 0 or value > 4.097 ->
    #             raise ArgumentError, "argument out of range - must be less than 4.097 volts"
    #         (channel != 0) and (channel != 1) ->
    #             raise ArgumentError, "channel must be 0 or 1"
    #         true -> true
    #     end
    # end

    # LED Functions

    def led_set(addr, led) do
        ledCMD(addr, 0x60, led, 0, 0)
    end

    def led_clr(addr, led) do
        ledCMD(addr, 0x61, led, 0, 0)
    end

    def led_toggle(addr, led) do
        ledCMD(addr, 0x62, led, 0, 0)
    end

    def led_get(addr, led) do
        ledCMD(addr, 0x63, led, 0, 1)
    end

    # LED private helpers

    defp ledCMD(_, _, led, _, _) when led < 0 or led > 1 do
        {:error, "Invalid LED value"}
    end
    defp ledCMD(addr, cmd, led, 0, bytes2return) do
        ppCMD(addr, cmd, led, 0, bytes2return)
    end

    # DOUT (digital output) functions

    def dout_set(addr, bit) do
        bitCMD(addr, 0x10, bit, 0, 0)
    end

    def dout_clear(addr, bit) do
        bitCMD(addr, 0x11, bit, 0, 0)
    end

    def dout_toggle(addr, bit) do
        bitCMD(addr, 0x12, bit, 0, 0)
    end

    def dout_write(addr, bit, value) do
        cmd = if value do
            0x10
        else
            0x11
        end
        bitCMD(addr, cmd, bit, 0, 0)
    end

    def dout_get_all(addr) do
        ppCMD(addr, 0x14, 0, 0, 1)
    end

    def dout_set_all(addr, byte) do
        if byte > 127 do
            raise ArgumentError, "byte argument out of range - must be less than 128"
        else
            ppCMD(addr, 0x13, byte, 0, 0)
        end
    end

    # DOUT private helpers

    defp bitCMD(addr, cmd, bit, arg, bytes2return) do
        if bit < 0 or bit > 6 do
            raise ArgumentError, "Invalid BIT specified (range 0-6)"
        else
            ppCMD(addr, cmd, bit, arg, bytes2return)
        end
    end


    @doc "Gets the address for a board (but you have to know it)"
    def getADDR(addr) do
        ppCMD(addr, 0x00, 0, 0, 1)
    end

    @doc "Issues a low level command to the DAQC board"

    @gpio_base_addr 8

    @spec ppCMD(integer, integer, integer, integer, integer) :: :ok | binary
    def ppCMD(addr, _, _, _, _) when addr > 7 do
        {:error, "Address parameter must be between 0 and 7"}
    end
    def ppCMD(addr, cmd, param1, param2, bytes2return) do
        io = get_io()
        GPIO.write(io.gpio_frame, 1)
        {:ok, _} = SPI.transfer(io.spi, <<addr+@gpio_base_addr, cmd, param1, param2>>)
        result = if bytes2return > 0 do
            (0..(bytes2return-1))
            |> Enum.map(fn (_) -> spi_read_single_byte(io.spi) end)
            |> :erlang.list_to_binary
        else
            :ok
        end
        GPIO.write(io.gpio_frame, 0)
        result
    end

    defp spi_read_single_byte(spi) do
        :timer.sleep(@dacq_read_delay)                      # see impl notes
        {:ok, <<byte>>} = SPI.transfer(spi, <<0x00>>)
        byte
    end

end