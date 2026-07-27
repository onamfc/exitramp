# Security model

The cardinal rule: **the gateway must never become an open relay.** A
misconfigured egress box is an anonymous proxy with your name on the bill —
and your allowlisted IP on someone else's abuse.

## What the default install enforces

- **Authentication is WireGuard keys.** There are no passwords. Each
  developer gets a unique keypair *and* a unique preshared key
  (post-quantum-hardening, and revocation stays per-person).
- **No open ports except SSH and WireGuard.** The nftables ruleset drops all
  other inbound traffic. The Terraform security group additionally restricts
  SSH to your admin CIDR at the AWS layer.
- **Forwarding is one-way by design.** The forward chain only allows
  `wg0 → internet` and established return traffic. Internet hosts cannot
  initiate connections through the box, and **peers cannot reach each other**
  (no lateral movement between developer laptops).
- **No HTTP proxy ports.** This project deliberately uses a VPN rather than
  Squid/Tinyproxy: there is no proxy port to accidentally leave open, and it
  works with every language and HTTP client without proxy-agent code.

## Operational practices

- **One config per human.** Never share a `.conf` between developers — you
  lose the ability to revoke individually. Configs contain private keys;
  treat them like SSH keys (delete the temporary copy in the home directory
  after importing).
- **Revoke on departure.** `sudo ./remove-peer.sh <name>` disconnects
  immediately.
- **Audit who's connected.** `sudo ./list-peers.sh` shows last handshakes;
  `sudo wg show` gives live transfer counts. Connection metadata only — the
  gateway never sees plaintext API payloads (TLS terminates at the vendor).
- **Keep API credentials off the gateway.** The box routes packets; your
  vendor API keys belong in your local backend's environment, not here.
- **Patch it.** It's one package doing one job, but it's still a public box:
  `apt upgrade` periodically, or enable `unattended-upgrades`.

## Things this does NOT protect against

- A compromised developer laptop can obviously send traffic through the
  gateway — same as any VPN.
- The vendor sees one IP for all developers. If you need per-developer
  attribution at the vendor, you need multiple gateways/EIPs.
- IPv6: the gateway is IPv4-only. Full-tunnel configs route `::/0` into the
  tunnel where it's dropped (preventing IPv6 leaks), but split-tunnel peers
  talking to an IPv6-capable vendor could bypass the tunnel via IPv6 — pin
  the vendor's IPv4 addresses or use full tunnel.
