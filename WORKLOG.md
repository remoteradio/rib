
## What I did

Setup the raw project as a git repository

```sh

# create the project

$ cd <some-working-directory-that-holds-your-projects>
$ mix new rib     # build a new bare-bones elixir project called "rib"
$ cd rib
$ git init   # initialize this as a GIT-controlled repository
```

Open that directory in your favorite editor (eg `mate .` or `code .` or `subl .`)

In mix.exs, added dependency on elixir_circuits libriaries for common i/o methods by modifying the deps function as follows:

```elixir
defp deps do
  [
    {:circuits_i2c, "~> 0.3"},
    {:circuits_spi, "~> 0.1"},
    {:circuits_gpio, "~> 0.1"},
    {:circuits_uart, "~> 1.3"}
  ]
end
```

Exit the editor and build the app...

```sh
mix deps.get
mix
```

Test that it runs, and play with tab-completion...
```sh
$ iex -S mix   # start elixir shell into running project
Erlang/OTP 21 [erts-10.3.4] [source] [64-bit] [smp:4:4] [ds:4:4:10] [async-threads:1] [hipe] [dtrace]

Interactive Elixir (1.8.1) - press Ctrl+C to exit (type h() ENTER for help)
iex(1)> Circuits.  # I hit tab to see what was loaded, resulted in the following:
GPIO    I2C     SPI     UART
iex(1)> Circuits.SPI.bus_names()
[]
iex(2)>
^C^C

```

Guess MAC OS doesn't define any SPI interfaces on the bus!!

Now, let's check in our project to github...

```

## Installing Mosquitto

```sh
$ wget http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key
sudo apt-key add mosquitto-repo.gpg.key
cd /etc/apt/sources.list.d
wget http://repo.mosquitto.org/debian/mosquitto-stretch.list
apt-get update
apt-get install mosquitto
```