#!/usr/bin/env bash
#
# exitramp — revoke a developer's access.
#
# Usage: sudo ./remove-peer.sh <name>
#
# Removes the peer from the live WireGuard interface and deletes the stored
# client config. Takes effect immediately — the developer is disconnected.
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
[ -n "$NAME" ] || fail "usage: $0 <name>"

WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
grep -q "^# BEGIN PEER ${NAME}\$" "$WG_CONF" || fail "peer '${NAME}' not found"

TMP="$(mktemp)"
awk -v name="$NAME" '
  $0 == "# BEGIN PEER " name { skip = 1; next }
  $0 == "# END PEER " name   { skip = 0; next }
  !skip { print }
' "$WG_CONF" > "$TMP"

# Collapse any doubled blank lines left behind by the removal.
awk 'NF { blank = 0 } !NF { blank++ } blank < 2' "$TMP" > "$WG_CONF"
rm -f "$TMP"

wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")
rm -f "${CLIENTS_DIR}/${NAME}.conf"

echo "[exitramp] peer '${NAME}' removed and disconnected."
