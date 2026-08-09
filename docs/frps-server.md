# Setting up the frps server

The add-on is only half of the picture. Somewhere with a public IP address you
need `frps`, the server half of frp, which accepts the tunnel and publishes it.
The cheapest VPS tier anywhere is plenty; a tunnel to one Home Assistant idles
at a few MB of RAM.

You need:

- a server reachable from the internet (VPS, dedicated box, anything with a
  static public address)
- root access to it, with systemd
- optionally a domain name, if you want `https://ha.example.com` instead of
  `http://203.0.113.9:8123`

## The quick way

```bash
git clone https://github.com/polarursus/homeassistant-frpc.git
cd homeassistant-frpc/server
sudo ./install-frps.sh
```

The script asks one question at a time, remembers your answers for next time,
and finishes by printing the exact add-on settings that match the server it just
configured. It downloads the release for your architecture, verifies its
checksum, creates an unprivileged `frps` user, writes `/etc/frp/frps.toml`,
installs a hardened systemd unit, and offers to open the ports in ufw or
firewalld.

Re-run it any time - option 2 reconfigures, option 3 reprints the client
settings and shows what is listening.

## The manual way

Substitute your architecture: `amd64`, `arm64`, `arm_hf` (ARMv7) or `arm`
(ARMv6).

```bash
VERSION=0.70.1
ARCH=amd64
cd /tmp
curl -fsSLO "https://github.com/fatedier/frp/releases/download/v${VERSION}/frp_${VERSION}_linux_${ARCH}.tar.gz"
curl -fsSLO "https://github.com/fatedier/frp/releases/download/v${VERSION}/frp_sha256_checksums.txt"
sha256sum --ignore-missing -c frp_sha256_checksums.txt
tar xzf "frp_${VERSION}_linux_${ARCH}.tar.gz"
sudo install -m 0755 "frp_${VERSION}_linux_${ARCH}/frps" /usr/local/bin/frps
```

Create a user that owns nothing:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin frps
sudo mkdir -p /etc/frp
```

Write `/etc/frp/frps.toml` - start from
[`server/examples/frps.toml`](../server/examples/frps.toml) - then lock it down,
since it holds the shared token:

```bash
sudo chown root:frps /etc/frp/frps.toml
sudo chmod 640 /etc/frp/frps.toml
```

Install [`server/examples/frps.service`](../server/examples/frps.service) as
`/etc/systemd/system/frps.service` and start it:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now frps
sudo systemctl status frps
```

## Choosing a transport

`serverPort` on the client must match whichever listener you enabled, and they
are different ports in the config even when you give them the same number.

| Transport | Server setting | When to use it |
| --- | --- | --- |
| `tcp` | `bindPort` | the default; start here |
| `kcp` | `kcpBindPort` | UDP. Holds up on lossy or high-latency links, and gets through where TCP to that port is throttled |
| `quic` | `quicBindPort` | UDP, newer than KCP, lower overhead |
| `websocket` / `wss` | `bindPort` | networks that only let HTTP(S) out |

KCP and QUIC trade bandwidth for resilience - they retransmit more eagerly than
TCP. On a clean fibre line plain TCP is faster.

## Getting HTTPS

**Put Caddy in front.** frps keeps a vhost port on loopback, Caddy owns 80 and
443 and gets certificates by itself:

```toml
# frps.toml
vhostHTTPPort = 8080
```

```caddyfile
# Caddyfile
ha.example.com {
	reverse_proxy 127.0.0.1:8080 {
		header_up Host {host}
	}
}
```

Point `ha.example.com` at the server with a DNS A record, open 80 and 443, and
set the add-on to `proxyType: http` with `customDomain: ha.example.com`.
WebSockets - which the Home Assistant frontend depends on - need no extra
configuration in either Caddy or frp.

There is a ready-made stack in
[`server/examples/docker-compose.yml`](../server/examples/docker-compose.yml).

**Or let frps do it**, with the `https2http` plugin and certificates you obtain
and renew yourself. It saves a process but means copying certificates onto the
server every renewal. The Caddy route is less work.

**Do not skip TLS.** A `tcp` proxy on `remotePort = 8123` puts a plain HTTP login
form on the public internet. It is fine for a five-minute test and nothing else.

## Hardening

- **Set a long token.** `openssl rand -hex 24`. Anyone with the token can
  publish tunnels through your server.
- **`transport.tls.force = true`** rejects clients that will not use TLS on the
  control connection.
- **Keep `allowPorts` narrow.** Without it any client can claim any port.
- **Keep the dashboard on `127.0.0.1`** and reach it through an SSH tunnel:
  `ssh -L 7500:127.0.0.1:7500 you@server`. It has no rate limiting.
- **Open only the ports you use.** The control port, plus 80/443 if you
  terminate TLS there. The `allowPorts` range does not need to be open unless
  you actually publish plain TCP tunnels on it.
- **Watch the logs.** `journalctl -u frps -f` shows every login attempt,
  successful or not.

## Checking that it works

```bash
sudo systemctl status frps
sudo ss -lnptu | grep frps
sudo journalctl -u frps -f
```

When a client connects you get a `client login info` line, followed by
`new proxy [name] success`. From another machine:

```bash
curl -I https://ha.example.com
```

A 200 or 302 means the whole chain is up.
