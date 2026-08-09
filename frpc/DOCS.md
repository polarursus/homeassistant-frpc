# FRP Client

Tunnels Home Assistant out to an [frp](https://github.com/fatedier/frp) server
(`frps`) that you control, so you can reach it from anywhere without opening a
port at home. Useful when your ISP puts you behind CGNAT, when your address
changes constantly, or when you would rather not expose your router at all.

You need an frps server before this add-on is of any use. See
[docs/frps-server.md](https://github.com/polarursus/homeassistant-frpc/blob/main/docs/frps-server.md)
for a walkthrough, including a menu-driven installer.

## Setup

1. Install the add-on and open its **Configuration** tab.
2. Fill in **frps server address**, **frps server port** and **Authentication
   token** to match your server.
3. Pick a **Proxy type**:
   - `http` or `https` if your server has vhost ports and you have a domain
     pointing at it. Fill in **Public domain**.
   - `tcp` if your server has no vhost ports. Fill in **Remote port** and reach
     Home Assistant at `your-server:that-port`.
4. Set **Transport protocol** to whatever your server listens on. `tcp` is the
   usual answer; use `kcp` or `quic` if your server only has the UDP ports open.
5. Save, then start the add-on and check the log.

Leave **Home Assistant address** at `127.0.0.1` and **Home Assistant port** at
`8123` unless you moved Home Assistant somewhere else. The add-on runs on the
host network, so loopback reaches Home Assistant directly.

## Tell Home Assistant about the proxy

Requests now arrive through frp, so Home Assistant sees them coming from
`127.0.0.1` rather than from the real visitor. Without the block below you get
`400 Bad Request` on login, and every login shows up as coming from localhost:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
```

Restart Home Assistant afterwards. Never widen `trusted_proxies` to
`0.0.0.0/0` - that lets anyone forge their own client address.

## Bring your own config

The options above cover one tunnel to Home Assistant. For anything more - two
proxies, `stcp`, plugins, per-proxy bandwidth limits - set **Configuration
mode** to `file` and point **Custom config file** at your own TOML:

```toml
serverAddr = "frp.example.com"
serverPort = 7000
auth.token = "..."

[[proxies]]
name = "homeassistant"
type = "http"
localIP = "127.0.0.1"
localPort = 8123
customDomains = ["ha.example.com"]

[[proxies]]
name = "esphome-ota"
type = "tcp"
localIP = "127.0.0.1"
localPort = 6052
remotePort = 6052
```

The file is passed to frpc untouched, so the full
[frp reference](https://github.com/fatedier/frp#documentation) applies. Both
`/share` and the add-on's own config directory are writable; write the file
with the Samba, File editor or Terminal add-on. The add-on restarts frpc when
you restart it, so restart the add-on after editing.

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `configMode` | `options` | `file` switches to your own TOML |
| `configFile` | `/share/frpc.toml` | only read when `configMode` is `file` |
| `serverAddr` | - | frps hostname or IP |
| `serverPort` | `7000` | `bindPort`, `kcpBindPort` or `quicBindPort` |
| `authToken` | - | must match `auth.token` on the server |
| `protocol` | `tcp` | `tcp`, `kcp`, `quic`, `websocket`, `wss` |
| `tls` | `true` | TLS on the control connection |
| `proxyName` | `homeassistant` | unique per frps server |
| `proxyType` | `http` | `http`, `https` or `tcp` |
| `customDomain` | - | for `http` and `https` |
| `remotePort` | `8123` | for `tcp` |
| `localIP` | `127.0.0.1` | where Home Assistant listens |
| `localPort` | `8123` | Home Assistant port |
| `useEncryption` | `true` | encrypt tunnel payload |
| `useCompression` | `true` | compress tunnel payload |
| `logLevel` | `info` | `trace`, `debug`, `info`, `warn`, `error` |

## When it does not connect

Raise **Log level** to `debug` and read the add-on log. The usual causes:

| Log line | Cause |
| --- | --- |
| `authorization failed` | token differs from the server's |
| `connection refused` / `i/o timeout` | wrong port, or the server's firewall drops it |
| `port already used` | another client holds that `remotePort` |
| `proxy name already exists` | another client uses the same `proxyName` |
| connects, but the browser 404s | the domain does not match `customDomains`, or the server has no vhost port |

More in
[docs/troubleshooting.md](https://github.com/polarursus/homeassistant-frpc/blob/main/docs/troubleshooting.md).
