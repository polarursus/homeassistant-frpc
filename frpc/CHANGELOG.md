# Changelog

## 1.1.1

- Read the options from `/data/options.json` instead of the Supervisor API.
  With `host_network` the Supervisor rejected the add-on's own token, so every
  option came back empty and the add-on stopped with a misleading
  "authToken is empty"

## 1.1.0

- Added `configMode: file` for using a hand-written frpc TOML file unchanged
- Added `tcp` proxy type with `remotePort`, for servers without vhost ports
- Added `armv7` and `armhf` builds
- Verify the frp release checksum during the image build
- Option labels and descriptions now show up in the Home Assistant UI

## 1.0.0

- Initial release, frp 0.70.1
- Single Home Assistant tunnel configured through add-on options
- `tcp`, `kcp`, `quic`, `websocket` and `wss` transports
