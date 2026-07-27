#!/usr/bin/env bash
#
# exitramp — create a WireGuard config for a developer.
#
# Usage:
#   sudo ./add-peer.sh <name> [options]
#
# Options:
#   --split <cidr[,cidr...]>  Selective routing: only these destination CIDRs
#                             go through the gateway. Default is a full tunnel
#                             (all traffic exits via the static IP).
#   --dns <ip>                DNS server pushed to the client on full tunnel
#                             (default: 1.1.1.1). Ignored in --split mode.
#   --endpoint <host:port>    Override the endpoint written into the client
#                             config (default: this server's public IP).
#
# Examples:
#   sudo ./add-peer.sh brandon
#   sudo ./add-peer.sh brandon --split 203.0.113.0/24,198.51.100.7/32
#
set -euo pipefail

STATE_DIR="/etc/exitramp"
CLIENTS_DIR="${STATE_DIR}/clients"

fail() { echo "[exitramp] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (try: sudo $0 $*)"
[ -f "${STATE_DIR}/config" ] || fail "server not installed — run install-server.sh first"
# shellcheck source=/dev/null
. "${STATE_DIR}/config"

NAME="${1:-}"
[ -n "$NAME" ] || fail "usage: $0 <name> [--split <cidrs>] [--dns <ip>] [--endpoint <host:port>]"
case "$NAME" in
  --*) fail "first argument must be the peer name" ;;
esac
echo "$NAME" | grep -Eq '^[A-Za-z0-9_-]{1,32}$' || fail "name must be 1-32 chars: letters, digits, - and _"
shift

SPLIT_CIDRS=""
CLIENT_DNS="1.1.1.1"
ENDPOINT_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --split)    SPLIT_CIDRS="${2:-}"; shift 2 ;;
    --dns)      CLIENT_DNS="${2:-}"; shift 2 ;;
    --endpoint) ENDPOINT_OVERRIDE="${2:-}"; shift 2 ;;
    *) fail "unknown option: $1" ;;
  esac
done

WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
[ -f "$WG_CONF" ] || fail "missing ${WG_CONF}"
grep -q "^# BEGIN PEER ${NAME}\$" "$WG_CONF" && fail "peer '${NAME}' already exists (remove-peer.sh first)"

# --- Allocate the next free VPN IP (.2 - .254) ------------------------------
CLIENT_IP=""
for i in $(seq 2 254); do
  candidate="${SUBNET_BASE}.${i}"
  if ! grep -q "AllowedIPs = ${candidate}/32" "$WG_CONF"; then
    CLIENT_IP="$candidate"
    break
  fi
done
[ -n "$CLIENT_IP" ] || fail "subnet ${WG_SUBNET} is full (253 peers)"

# --- Resolve the endpoint clients will connect to ---------------------------
if [ -n "$ENDPOINT_OVERRIDE" ]; then
  ENDPOINT="$ENDPOINT_OVERRIDE"
elif [ -n "${SERVER_ENDPOINT:-}" ]; then
  ENDPOINT="${SERVER_ENDPOINT}:${WG_PORT}"
else
  PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://checkip.amazonaws.com)" \
    || fail "could not auto-detect public IP; pass --endpoint <host:port>"
  ENDPOINT="${PUBLIC_IP}:${WG_PORT}"
fi

# --- Keys -------------------------------------------------------------------
umask 077
CLIENT_PRIVATE_KEY="$(wg genkey)"
CLIENT_PUBLIC_KEY="$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)"
PRESHARED_KEY="$(wg genpsk)"
SERVER_PUBLIC_KEY="$(cat "${STATE_DIR}/server.pub")"

# --- Routing mode -----------------------------------------------------------
if [ -n "$SPLIT_CIDRS" ]; then
  # Selective: only vendor CIDRs ride the tunnel; everything else stays local.
  CLIENT_ALLOWED_IPS="${SPLIT_CIDRS//,/, }"
  DNS_LINE=""
else
  # Full tunnel. ::/0 is included so IPv6 traffic is captured (and dropped by
  # the IPv4-only gateway) instead of leaking around the tunnel.
  CLIENT_ALLOWED_IPS="0.0.0.0/0, ::/0"
  DNS_LINE="DNS = ${CLIENT_DNS}"
fi

# --- Register the peer on the server ----------------------------------------
cat >> "$WG_CONF" <<EOF

# BEGIN PEER ${NAME}
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEY}
PresharedKey = ${PRESHARED_KEY}
AllowedIPs = ${CLIENT_IP}/32
# END PEER ${NAME}
EOF
wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")

# --- Write the client config ------------------------------------------------
mkdir -p "$CLIENTS_DIR"
CLIENT_CONF="${CLIENTS_DIR}/${NAME}.conf"
{
  echo "[Interface]"
  echo "PrivateKey = ${CLIENT_PRIVATE_KEY}"
  echo "Address = ${CLIENT_IP}/32"
  [ -n "$DNS_LINE" ] && echo "$DNS_LINE"
  echo ""
  echo "[Peer]"
  echo "PublicKey = ${SERVER_PUBLIC_KEY}"
  echo "PresharedKey = ${PRESHARED_KEY}"
  echo "Endpoint = ${ENDPOINT}"
  echo "AllowedIPs = ${CLIENT_ALLOWED_IPS}"
  echo "PersistentKeepalive = 25"
} > "$CLIENT_CONF"

# /etc/exitramp is root-only; drop a copy where the admin can scp it.
COPY_PATH=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
  SUDO_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
  if [ -n "$SUDO_HOME" ] && [ -d "$SUDO_HOME" ]; then
    COPY_PATH="${SUDO_HOME}/${NAME}.conf"
    cp "$CLIENT_CONF" "$COPY_PATH"
    chown "$SUDO_USER" "$COPY_PATH"
    chmod 600 "$COPY_PATH"
  fi
fi

echo
echo "  ────────────────────────────────────────────────────────"
echo "  Peer '${NAME}' created."
echo
echo "  VPN IP:     ${CLIENT_IP}"
echo "  Mode:       $([ -n "$SPLIT_CIDRS" ] && echo "split tunnel (${SPLIT_CIDRS})" || echo "full tunnel")"
echo "  Config:     ${CLIENT_CONF}"
echo
echo "  Import it into the WireGuard app (macOS/Windows/Linux), or"
echo "  scan this QR code from the iOS/Android WireGuard app:"
echo "  ────────────────────────────────────────────────────────"
if command -v qrencode >/dev/null 2>&1; then
  qrencode -t ansiutf8 < "$CLIENT_CONF"
else
  echo "  (install qrencode for a QR code)"
fi
echo
if [ -n "$COPY_PATH" ]; then
  echo "  A copy was placed at ${COPY_PATH} — fetch it from your laptop:"
  echo "    scp ${SUDO_USER}@<server>:${NAME}.conf ."
  echo "  (delete it after importing: it contains the private key)"
fi
