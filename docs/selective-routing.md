# Selective (split-tunnel) routing

By default, `add-peer.sh` creates a **full tunnel**: while the VPN is
connected, *all* of your laptop's traffic exits through the gateway's static
IP. That's the simplest mode and requires zero application changes — but your
browsing also rides through the gateway while connected.

**Split tunnel** sends only traffic destined for specific vendor IP ranges
through the gateway. Everything else uses your normal connection.

## Creating a split-tunnel peer

```bash
sudo ./add-peer.sh brandon --split 203.0.113.0/24,198.51.100.7/32
```

The generated client config's `AllowedIPs` becomes the vendor CIDRs instead of
`0.0.0.0/0`. WireGuard installs routes for exactly those ranges — that's the
whole mechanism. No server-side change is needed.

## Finding a vendor's IP ranges

Routing works on IPs, not hostnames, so you need the vendor's addresses:

```bash
# What does the API hostname resolve to right now?
dig +short api.vendor.com

# Who owns that IP / what's the announced block?
whois -h whois.radb.net <ip> | grep route
```

Some vendors publish official IP ranges (ask their support — vendors that
require IP allowlisting usually have this documented). AWS-hosted vendors may
fall inside published AWS ranges, but those are huge — prefer the vendor's own
list.

## Caveats

- **CDNs and rotating IPs.** If the vendor sits behind Cloudflare/Fastly/etc.,
  its IPs change and split tunnel becomes a maintenance burden. Use full
  tunnel instead, and just connect only while testing.
- **DNS.** Split-tunnel configs don't override your DNS. If the vendor
  resolves differently inside vs. outside their network, resolve manually and
  verify with `curl -v`.
- **Updating ranges.** To change a peer's CIDRs, edit `AllowedIPs` in the
  client's `.conf` and re-import it — or `remove-peer.sh` + `add-peer.sh`
  with the new list.

## Verifying

With the tunnel up:

```bash
# Should show your NORMAL home IP (not routed through gateway):
curl -4 -s https://checkip.amazonaws.com

# Should reach the vendor FROM the gateway IP — check the vendor's logs,
# or if one of the split CIDRs contains a host you control, hit it and
# check the source IP it sees.
```

For full-tunnel peers, `client/check-ip.sh <gateway-ip>` confirms everything
is routing through the gateway.
