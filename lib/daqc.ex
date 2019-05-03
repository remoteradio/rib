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

    @doc """
    Return a list of boards that are present

    PRIOR PYTHON CODE:
    def Poll():
        ppFoundCount=0
        for i in range (0,8):
            rtn = getADDR(i)
            if ((rtn-8)==i):
                print "ppDAQC board found at address",rtn-8
                ppFoundCount += 1
        if (ppFoundCount == 0):
            print "No ppDAQC boards found"
    """
    def discover_boards(ref) do
        Enum.reject(0..7, &(! board_present(ref, &1)))
    end

    @doc """
    Return status of board on this address

    {:ok, :active}              Apparently found a legitimate ppDAQC board on this address
    {:error, :misconfigured}    Got a response on this address, but wrong response
    term                        Response from ppCMD
    """
    @spec board_present(term, integer) :: bool
    def board_present(ref, addr) do
        proper_response_addr = addr+8
        proper_response = <<proper_response_addr>>
        case getADDR(ref, addr) do
            {:ok, ^proper_response} -> true
            _ -> false
        end
    end

    @doc """
    Straight port of python getADDR function, not sure what it does

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

    3.  On reads, we are sleeping 1ms rather than the 0.1ms specified by the python
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
            :timer.sleep(1)                                       # note 3
            SPI.transfer(ref.spi, String.duplicate(<<0>>,bytes2return))
        else
            {:ok, :written}
        end
        GPIO.write(ref.gpio_frame, 0)
        result
    end

end