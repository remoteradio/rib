# Rib

Beginnings of "RIB" (Radio In Box) Controller

## Build/Run

```sh
$ mix deps.get 			# get dependencies
$ mix					# compile/run
```

To get a shell into the running application:

```sh
$ iex -S mix
```

## Key Modules

- Rib.Application - Starts and supervises everything related to RIB
- Rib.MQTT - Manages connection to Mosquitto MQTT Server
- DAQC - Elixir support for Pi-Plates DAQC Board (eventually may move to a dependent library)

## Requires MQTT on Localhost

`RIB` expects to be able to make a connection to an MQTT server on localhost in order to work properly.  You can install `mosquitto` on MacOS for test purposes using the following:

```sh
$ brew install mosquitto
$ brew services start mosquitto
```

