# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-07-27

### Added

- `install-server.sh`: one-shot, idempotent gateway setup for Ubuntu/Debian —
  WireGuard, IPv4 forwarding, and an nftables ruleset that denies all inbound
  traffic except SSH and WireGuard and only forwards VPN → internet (peers
  cannot reach each other; the box cannot be used as an open relay).
- `add-peer.sh`: per-developer onboarding with unique keypair + preshared key,
  QR code output, full-tunnel or split-tunnel (`--split <vendor-cidrs>`)
  routing, and live reload without disconnecting existing peers.
- `remove-peer.sh`: immediate revocation of a developer's access.
- `list-peers.sh`: peer inventory with live last-handshake status.
- `client/check-ip.sh`: laptop-side verification that traffic egresses via the
  gateway.
- `terraform/aws`: fully automated deployment — EC2 instance (t4g.nano by
  default) + Elastic IP, security group locked to an admin CIDR for SSH, and
  the install script run via cloud-init.
- Documentation: security model (`docs/security.md`) and selective routing
  guide (`docs/selective-routing.md`).

### Verified

- End-to-end on AWS (us-east-2): cloud-init install, peer creation, WireGuard
  handshake over the public internet, and client traffic egressing from the
  Elastic IP. Revocation confirmed to cut a connected peer immediately.

[Unreleased]: https://github.com/onamfc/exitramp/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/onamfc/exitramp/releases/tag/v0.1.0
