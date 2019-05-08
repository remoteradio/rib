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
