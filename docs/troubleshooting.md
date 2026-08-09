# Troubleshooting

Work from both ends: the add-on log in Home Assistant, and
`journalctl -u frps -f` on the server. Raise the add-on's **Log level** to
`debug` first - `info` hides the reason for most failures.

## The client will not connect

| Log line | What it means |
| --- | --- |
| `authorization failed` | the tokens differ. They are compared byte for byte - watch for a trailing space |
| `connection refused` | nothing is listening on that port. Wrong port, or frps is not running |
| `i/o timeout` | a firewall is dropping the packets. Check the server firewall *and* the cloud provider's security group |
| `tls: first record does not look like a TLS handshake` | the server does not expect TLS on that port. Turn off **Encrypt the control connection**, or fix `transport.tls.force` |
| `port already used` | another client already holds that `remotePort` |
| `proxy name already exists` | two clients are using the same `proxyName`. They must be unique per server |
| `dial tcp ...: no such host` | `serverAddr` does not resolve |

A UDP transport that times out while TCP works usually means the UDP port is
closed. Cloud firewalls default to TCP-only rules; the UDP rule is separate.

Check what the server is actually listening on:

```bash
sudo ss -lnptu | grep frps
```

`kcpBindPort` and `quicBindPort` appear as `udp`. If you configured KCP but only
see a `tcp` line, frps did not pick up the setting - check for a typo and
restart it.

## Connected, but the browser gets nothing

The tunnel is up (`new proxy [name] success` in the server log) and the page
still fails.

- **404 or "no route found"** - the hostname you typed does not match
  `customDomains`. They must be identical, and the DNS record must point at the
  frps server.
- **Nothing on the port** - with `proxyType: http`, frps only answers on
  `vhostHTTPPort`. If that is 8080, either browse to `:8080` or put a reverse
  proxy on 80/443.
- **Certificate warnings** - frps does not issue certificates. Terminate TLS in
  Caddy or nginx in front of it.

## 400 Bad Request when logging in

Missing `trusted_proxies`. See [home-assistant.md](home-assistant.md).

## The frontend loads, then goes blank or keeps reconnecting

The WebSocket connection is being cut. frp itself passes WebSockets through
untouched, so look at whatever else is in the path: an nginx without
`proxy_set_header Upgrade`, or an idle timeout somewhere killing long-lived
connections. Caddy's `reverse_proxy` handles this correctly with no extra
configuration.

## Everything is slow

- Turn off **Compress tunnel traffic** if the tunnel carries camera streams -
  compressing already-compressed video wastes CPU on both ends.
- KCP and QUIC retransmit more aggressively than TCP. On a clean line, plain
  `tcp` is faster.
- Check where the server is. Every request crosses the internet twice; a VPS on
  another continent adds that round trip to every click.

## The add-on will not start at all

- `serverAddr is empty` - fill in the Configuration tab.
- `configMode is 'file' but ... does not exist` - either the path is wrong or
  the file was never created. `/share/frpc.toml` is reachable from the Samba,
  File editor and Terminal add-ons.
- A build failure right after installing usually means the machine could not
  reach GitHub to download frp. Check the Supervisor log:
  `ha supervisor logs`.

## Getting more detail

```bash
# Server
sudo journalctl -u frps -n 100 --no-pager
sudo systemctl status frps

# Home Assistant, from a Terminal add-on
ha addons logs local_frpc
```

Validate a hand-written client config before restarting the add-on:

```bash
frpc verify -c /share/frpc.toml
```
