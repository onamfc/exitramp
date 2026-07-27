#!/usr/bin/env bash
#
# exitramp — list registered peers and their live connection status.
#
# Usage: sudo ./list-peers.sh
#
set -euo pipefail

STATE_DIR="/etc/exitramp"

fail() { echo "[exitramp] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (try: sudo $0)"
[ -f "${STATE_DIR}/config" ] || fail "server not installed — run install-server.sh first"
# shellcheck source=/dev/null
. "${STATE_DIR}/config"

WG_CONF="/etc/wireguard/${WG_IFACE}.conf"

printf "%-20s %-16s %-46s %s\n" "NAME" "VPN IP" "PUBLIC KEY" "LAST HANDSHAKE"

awk '
  /^# BEGIN PEER / { name = $4; inpeer = 1; next }
  /^# END PEER /   { print name, ip, pub; inpeer = 0; next }
  inpeer && /^PublicKey = /  { pub = $3 }
  inpeer && /^AllowedIPs = / { ip = $3; sub(/\/32$/, "", ip) }
' "$WG_CONF" | while read -r name ip pub; do
  handshake="$(wg show "$WG_IFACE" latest-handshakes | awk -v k="$pub" '$1 == k { print $2 }')"
  if [ -z "${handshake:-}" ] || [ "$handshake" = "0" ]; then
    status="never"
  else
    now="$(date +%s)"
    ago=$(( now - handshake ))
    if   [ "$ago" -lt 120 ];  then status="${ago}s ago (online)"
    elif [ "$ago" -lt 3600 ]; then status="$(( ago / 60 ))m ago"
    else                           status="$(( ago / 3600 ))h ago"
    fi
  fi
  printf "%-20s %-16s %-46s %s\n" "$name" "$ip" "$pub" "$status"
done
