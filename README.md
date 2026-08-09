# FRP Client add-on for Home Assistant

Reach your Home Assistant from anywhere without opening a single port at home.
The add-on runs [frp](https://github.com/fatedier/frp)'s client and keeps an
outbound tunnel to an `frps` server you control, which publishes it on a domain
of your choosing.

```
browser --HTTPS--> your server ==== encrypted tunnel ====> home
                   Caddy + frps                           frpc add-on
                                                              |
                                                              v
                                                     Home Assistant :8123
```

Because the tunnel is opened from inside your network, this works where port
forwarding does not: CGNAT, mobile broadband, a router you do not administer, a
dynamic address that changes weekly.

## Why another frpc add-on

The existing ones stopped at frp 0.53 and build their config by running `sed`
over a fixed template, so there is no way to pick a transport, turn TLS off, or
describe more than one tunnel. This one ships current frp, exposes the settings
that matter, and gets out of the way entirely when you hand it your own TOML.

- **frp 0.70.1**, checksum-verified at build time
- **All transports** - `tcp`, `kcp`, `quic`, `websocket`, `wss`. KCP and QUIC get
  through where TCP is throttled
- **Bring your own config** - point it at an `frpc.toml` and it runs that
  untouched, for multiple proxies, `stcp`, plugins, anything frp supports
- **amd64, aarch64, armv7, armhf**
- **A menu-driven server installer**, because the client is the easy half

## Install

In Home Assistant open Settings, then **Apps** (called **Add-ons** before the
2026 releases, and reachable at `/app` if it is missing from Settings). Open
the store, then the three-dot menu in the top right, and pick Repositories.
Add:

```
https://github.com/polarursus/homeassistant-frpc
```

Then install **FRP Client**, fill in your server address, port and token, and
start it. Full walkthrough: [docs/home-assistant.md](docs/home-assistant.md).

One thing you must not skip - Home Assistant rejects proxied logins with
`400 Bad Request` until you add this to `configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
```

## The server half

No frps server yet? On any VPS with a public address:

```bash
git clone https://github.com/polarursus/homeassistant-frpc.git
cd homeassistant-frpc/server
sudo ./install-frps.sh
```

It asks one question at a time, remembers your answers, verifies what it
downloads, writes a hardened systemd unit, offers to open the firewall, and
prints the add-on settings that match. Details and the manual route:
[docs/frps-server.md](docs/frps-server.md).

## Documentation

| | |
| --- | --- |
| [frps-server.md](docs/frps-server.md) | installing and hardening the server, transports, HTTPS with Caddy |
| [home-assistant.md](docs/home-assistant.md) | add-on setup, `trusted_proxies`, running frpc outside Home Assistant |
| [troubleshooting.md](docs/troubleshooting.md) | what each error in the logs actually means |
| [frpc/DOCS.md](frpc/DOCS.md) | every add-on option, and the custom config mode |

## Repository layout

```
frpc/                 the add-on
server/
  install-frps.sh     menu-driven server installer
  examples/           frps.toml, systemd unit, docker-compose, Caddyfile
docs/                 guides
```

## Security

The tunnel carries your home automation, including door locks and cameras.

- Use a long shared token - `openssl rand -hex 24`
- Leave **Encrypt the control connection** on, and set
  `transport.tls.force = true` on the server
- Terminate HTTPS properly; a `tcp` proxy on port 8123 is a plain HTTP login
  form on the public internet
- Turn on Home Assistant's IP bans and multi-factor authentication
- Never set `trusted_proxies` to `0.0.0.0/0`

If you only ever connect from your own devices, a VPN - WireGuard, Tailscale -
exposes less. frp earns its place when you need a real public URL: webhooks,
sharing access, voice assistant integrations.

## License

MIT. frp itself is Apache 2.0 and is downloaded from its official releases at
build time.
