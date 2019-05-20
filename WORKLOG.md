
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

## Installing Mosquitto on the Raspberry PI

Mosquitto is a (relatively) lightweight MQTT broker(server) that runs on the Raspberry Pi.

We are going to use the latest Mosquitto (1.6.x), because it supports MQTT V5, with the modern V5 request-response messages, which are useful to control devices reliably.   Because the Raspbian repo only contains Mosquitto 1.4, without support for MQTT V5, we need to install from mosquitto.org's own package repository, rather than the stock Raspberry PI repo.

```sh
# First, install the GPG key to the Mosquitto repo on your pi

$ cd ~ # your home directory
$ wget http://repo.mosquitto.org/debian/mosquitto-repo.gpg.key
$ sudo apt-key add mosquitto-repo.gpg.key

# Tell Raspbian to allow access to the mosquitto package repo for
# Debian "stretch" on which raspbian is based...

$ cd /etc/apt/sources.list.d
$ sudo wget http://repo.mosquitto.org/debian/mosquitto-stretch.list

# Now, update the APT package repo and install mosquitto server
$ sudo apt update
$ sudo apt install mosquitto

# Install the mosquitto-clients (if desired, for local CLI debugging)
$ sudo apt install mosquitto-clients
```

That is it, mosquitto should be up and running now!

## Mosquitto on MAC OS X (not required)

This would be needed only for exploring mirroring the state of the broker on the Raspberry Pi to another broker.

```sh
$ brew update
$ brew install mosquitto
```
You can make changes to the configuration by editing:
`/usr/local/etc/mosquitto/mosquitto.conf`
To have launchd start mosquitto now and restart at login:
`$ brew services start mosquitto`
Or, if you don't want/need a background service you can just run:
`$ mosquitto -c /usr/local/etc/mosquitto/mosquitto.conf`

# Other Topics to Investigate

- Grafana and InfluxDB from MQTT for TSD
- OpenHAB
- Blynk (pi)
- Plotly.js
- Graphite/Carbon
