# The Home Assistant side

## Installing the add-on

Open Settings, Add-ons, Add-on Store, then the three-dot menu in the top right
and pick Repositories. Add:

```
https://github.com/polarursus/homeassistant-frpc
```

Refresh the page, and **FRP Client** appears under a section named after this
repository. Install it, fill in the Configuration tab, start it.

On Home Assistant OS versions from 2026 onward the menu is called **Apps**
rather than Add-ons - same thing, renamed.

## Trusting the proxy

This is the step everyone misses, and it fails in a confusing way: the login
page loads, you type your password, and you get `400 Bad Request`.

Traffic now arrives through frp, so Home Assistant sees every request coming
from `127.0.0.1` instead of from the real visitor. Add this to
`configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
```

Restart Home Assistant. `127.0.0.1` is the right entry because the add-on runs
on the host network - it hands the connection to Home Assistant over loopback.
If you instead run frpc on a different machine on your LAN, use that machine's
address.

`use_x_forwarded_for` tells Home Assistant to read the client address out of the
`X-Forwarded-For` header, and `trusted_proxies` says whose word it will take for
it. Anything in that list can claim to be any IP address, which is why
`0.0.0.0/0` - suggested by a depressing number of tutorials - is a bad idea: it
lets an attacker forge their address and walk straight past your IP bans.

## Worth turning on

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 127.0.0.1
  ip_ban_enabled: true
  login_attempts_threshold: 5
```

And in your profile, enable multi-factor authentication. Your Home Assistant is
now on the public internet; a leaked password should not be enough on its own.

## Reaching it

With `proxyType: http` and a domain: `https://ha.example.com`.

With `proxyType: tcp`: `http://your-server:8123` - unencrypted, so treat it as a
temporary arrangement.

The companion mobile app works over either. Set the external URL under Settings,
System, Network to the same address so notifications and camera thumbnails
resolve correctly.

## Running frpc somewhere else instead

The add-on is convenient because it lives and dies with Home Assistant, but
nothing stops you running frpc on another always-on machine on the LAN:

```yaml
services:
  frpc:
    image: snowdreamtech/frpc:0.70.1
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./frpc.toml:/etc/frp/frpc.toml:ro
```

Set `localIP` to the Home Assistant machine's LAN address rather than
`127.0.0.1`, and put that machine's address in `trusted_proxies`. The trade-off:
remote access now depends on two machines being up instead of one.
