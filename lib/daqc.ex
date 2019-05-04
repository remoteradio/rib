defmodule DAQC do

    @moduledoc """
    A more or less direct translation of portions (not yet complete)
    of ppDAQC.py, which is the python code to do SPI I/O for the PyPlates
    DAQC board.   Converts to Elixir idioms where appropriate.
    """

    # allow ease of referencing Circuits.GPIO.whatever(), as just GPIO.whatever()

    alias Circuits.SPI
    alias Circuits.GPIO

    @doc """
    Init DACQ and return term (ref) to use with further actions
    """

    @ppFRAME        25
    @ppINT          22
    @ppSPI          "spidev0.1"

    def init do
        {:ok, gpio_frame} = GPIO.open(@ppFRAME, :output)
        {:ok, gpio_int} = GPIO.open(@ppINT, :input)
        :ok = GPIO.set_pull_mode(gpio_int, :pullup)
        {:ok, spi_ref} = SPI.open(@ppSPI)
        {:ok, %{
            gpio_frame: gpio_frame,
            gpio_int: gpio_int,
            spi: spi_ref}
        }
    end

    @doc "Return a list of addresses where DACQ boards are present"
    def discover_boards(ref) do
        Enum.reject(0..7, &(! board_present?(ref, &1)))
    end

    @doc "Predicate for presense of a board on specified address"
    @spec board_present?(term, integer) :: bool
    def board_present?(ref, addr) do
        proper_response_addr = addr+8
        proper_response = <<proper_response_addr>>
        case getADDR(ref, addr) do
            {:ok, ^proper_response} -> true
            _ -> false
        end
    end

    @doc "Read from the ADC (channel 8 is double scaled for some reason)"
    def adc_read(ref, addr, channel) when channel < 7 do
        adc_read_scaled(ref, addr, channel)
    end
    def adc_read(ref, addr, channel) when channel == 8 do
        2 * adc_read_scaled(ref, addr, channel)
    end

    defp adc_read_scaled(ref, addr, channel) do
        {:ok, <<value::big-unsigned-integer-size(16)>>} = ppCMD(ref, addr, 0x30, channel, 0, 2)
        Float.round((value * 4.096/1024), 3)
    end

    @doc "Read all ADC as list"
    def adc_read_all(_ref, _addr), do: raise "Not Yet Implemented"


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

    def led_set(ref, addr, led) do
        ledCMD(ref, addr, 0x60, led, 0, 0)
    end

    def led_clr(ref, addr, led) do
        ledCMD(ref, addr, 0x61, led, 0, 0)
    end

    def led_toggle(ref, addr, led) do
        ledCMD(ref, addr, 0x62, led, 0, 0)
    end

    def led_get(ref, addr, led) do
        ledCMD(ref, addr, 0x63, led, 0, 1)
    end

    # LED private helpers

    defp ledCMD(_, _, _, led, _, _) when led < 0 or led > 1 do
        {:error, "Invalid LED value"}
    end
    defp ledCMD(ref, addr, cmd, led, 0, bytes2return) do
        ppCMD(ref, addr, cmd, led, 0, bytes2return)
    end

    # DOUT (digital output) functions

    def dout_set(ref, addr, bit) do
        bitCMD(ref, addr, 0x10, bit, 0, 0)
    end

    def dout_clear(ref, addr, bit) do
        bitCMD(ref, addr, 0x11, bit, 0, 0)
    end

    def dout_toggle(ref, addr, bit) do
        bitCMD(ref, addr, 0x12, bit, 0, 0)
    end

    def dout_write(ref, addr, bit, value) do
        cmd = if value do
            0x10
        else
            0x11
        end
        bitCMD(ref, addr, cmd, bit, 0, 0)
    end

    def dout_get_all(ref, addr) do
        {:ok, <<result>>} = ppCMD(ref, addr, 0x14, 0, 0, 1)
        result
    end

    def dout_set_all(ref, addr, byte) do
        if byte > 127 do
            raise ArgumentError, "byte argument out of range - must be less than 128"
        else
            ppCMD(ref, addr, 0x13, byte, 0, 0)
        end
    end

    # DOUT private helpers

    defp bitCMD(ref, addr, cmd, bit, arg, bytes2return) do
        if bit < 0 or bit > 6 do
            raise ArgumentError, "Invalid BIT specified (range 0-6)"
        else
            ppCMD(ref, addr, cmd, bit, arg, bytes2return)
        end
    end

    @doc """
    Straight port of python getADDR function, used for discovery

    Python:
    def getADDR(addr):
        if (addr>MAXADDR):
            return "ERROR: address out of range - must be less than", MAXADDR-1
        resp=ppCMD(addr,0x00,0,0,1)
        return resp[0]
    """
    def getADDR(ref, addr), do: ppCMD(ref, addr, 0x00, 0, 0, 1)

    @doc """
    Issues a low level command to the DAQC board

    Translated from python source:
    def ppCMD(addr,cmd,param1,param2,bytes2return):
        global GPIObaseADDR
        arg = range(4)
        resp = []
        arg[0]=addr+GPIObaseADDR;
        arg[1]=cmd;
        arg[2]=param1;
        arg[3]=param2;
        GPIO.output(ppFRAME,True)
        null = spi.writebytes(arg)
        if bytes2return>0:
            time.sleep(.0001)
            for i in range(0,bytes2return):
                dummy=spi.readbytes(1)
                resp.append(dummy[0])
        GPIO.output(ppFRAME,False)
        return resp

    Translation Notes:

    1.  On reads, we are sleeping 1ms rather than the 0.1ms specified by the python
        implementation, however in python a sleep() relinquishes the cpu to the
        OS anyway, which results in a minimum OS scheduler latency of about
        5-10ms in linux, whereas this only releases the CPU to the erlang VM,
        which will hold fairly tightly to 1ms, so the elixir implementation should
        usually result in same or less latency than the python version.

    """

    @gpio_base_addr 8

    def ppCMD(_, addr, _, _, _, _) when addr > 7 do
        {:error, "Address parameter must be between 0 and 7"}
    end
    def ppCMD(ref, addr, cmd, param1, param2, bytes2return) do
        GPIO.write(ref.gpio_frame, 1)
        {:ok, _} = SPI.transfer(ref.spi, <<addr+@gpio_base_addr, cmd, param1, param2>>)
        result = if bytes2return > 0 do
            :timer.sleep(1)                                       # note 1
            SPI.transfer(ref.spi, String.duplicate(<<0>>,bytes2return))
        else
            {:ok, :written}
        end
        GPIO.write(ref.gpio_frame, 0)
        result
    end

end