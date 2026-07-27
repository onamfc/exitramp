#!/usr/bin/env bash
#
# exitramp — turn a fresh Ubuntu/Debian VM into a WireGuard egress gateway.
#
# Developers connect over WireGuard and their traffic (all of it, or only
# selected vendor CIDRs) leaves this machine's static public IP — the IP you
# hand to vendors that require allowlisting.
#
# Safe to run non-interactively (e.g. as cloud-init user data). Idempotent:
# re-running upgrades packages and reapplies config without touching peers.
#
# Configuration (environment variables, all optional):
#   WG_PORT          UDP port WireGuard listens on        (default: 51820)
#   WG_SUBNET        VPN subnet, must be a /24            (default: 10.88.0.0/24)
#   WG_IFACE         WireGuard interface name             (default: wg0)
#   SSH_PORT         SSH port to allow through firewall   (default: 22)
#   SETUP_FIREWALL   "yes" to install nftables ruleset    (default: yes)
#   EGRESS_IFACE     Public network interface             (default: auto-detect)
#   SERVER_ENDPOINT  Public IP/host clients connect to    (default: detected per-peer)
#
set -euo pipefail

WG_PORT="${WG_PORT:-51820}"
WG_SUBNET="${WG_SUBNET:-10.88.0.0/24}"
WG_IFACE="${WG_IFACE:-wg0}"
SSH_PORT="${SSH_PORT:-22}"
SETUP_FIREWALL="${SETUP_FIREWALL:-yes}"
SERVER_ENDPOINT="${SERVER_ENDPOINT:-}"

STATE_DIR="/etc/exitramp"
CLIENTS_DIR="${STATE_DIR}/clients"

log()  { echo "[exitramp] $*"; }
fail() { echo "[exitramp] ERROR: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must run as root (try: sudo $0)"
command -v apt-get >/dev/null 2>&1 || fail "only Ubuntu/Debian are supported (apt-get not found)"

case "$WG_SUBNET" in
  *.0/24) ;;
  *) fail "WG_SUBNET must be a /24 ending in .0 (got: $WG_SUBNET)" ;;
esac
SUBNET_BASE="${WG_SUBNET%.0/24}"        # e.g. 10.88.0
SERVER_VPN_IP="${SUBNET_BASE}.1"

log "installing packages (wireguard, nftables, qrencode, curl, iproute2)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq wireguard nftables qrencode curl iproute2 >/dev/null

# --- IP forwarding ---------------------------------------------------------
log "enabling IPv4 forwarding..."
cat > /etc/sysctl.d/99-exitramp.conf <<EOF
net.ipv4.ip_forward = 1
EOF
sysctl -p /etc/sysctl.d/99-exitramp.conf >/dev/null

# --- Detect egress interface ----------------------------------------------
if [ -z "${EGRESS_IFACE:-}" ]; then
  EGRESS_IFACE="$(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<NF;i++) if ($i=="dev") print $(i+1); exit}')"
fi
[ -n "$EGRESS_IFACE" ] || fail "could not detect egress interface; set EGRESS_IFACE explicitly"
log "egress interface: ${EGRESS_IFACE}"

# --- Server keys and WireGuard config --------------------------------------
umask 077
mkdir -p "$STATE_DIR" "$CLIENTS_DIR"

if [ ! -f "${STATE_DIR}/server.key" ]; then
  log "generating server keypair..."
  wg genkey > "${STATE_DIR}/server.key"
  wg pubkey < "${STATE_DIR}/server.key" > "${STATE_DIR}/server.pub"
fi
SERVER_PRIVATE_KEY="$(cat "${STATE_DIR}/server.key")"

WG_CONF="/etc/wireguard/${WG_IFACE}.conf"
if [ ! -f "$WG_CONF" ]; then
  log "writing ${WG_CONF}..."
  cat > "$WG_CONF" <<EOF
[Interface]
Address = ${SERVER_VPN_IP}/24
ListenPort = ${WG_PORT}
PrivateKey = ${SERVER_PRIVATE_KEY}
SaveConfig = false
EOF
else
  log "${WG_CONF} already exists; leaving peers untouched"
fi

# --- Persist settings for the peer-management scripts -----------------------
cat > "${STATE_DIR}/config" <<EOF
WG_PORT=${WG_PORT}
WG_SUBNET=${WG_SUBNET}
WG_IFACE=${WG_IFACE}
SUBNET_BASE=${SUBNET_BASE}
SERVER_ENDPOINT=${SERVER_ENDPOINT}
EOF

# --- Firewall (nftables) ----------------------------------------------------
# Forwarding is only allowed wg -> internet (and return traffic). Peers cannot
# reach each other and nothing on the internet can use this box as a relay.
if [ "$SETUP_FIREWALL" = "yes" ]; then
  log "writing nftables ruleset..."
  if [ -f /etc/nftables.conf ] && ! grep -q "exitramp" /etc/nftables.conf; then
    cp /etc/nftables.conf "/etc/nftables.conf.pre-exitramp.bak"
    log "backed up existing /etc/nftables.conf"
  fi
  cat > /etc/nftables.conf <<EOF
#!/usr/sbin/nft -f
# Managed by exitramp. Re-running install-server.sh overwrites this file.
flush ruleset

table inet exitramp {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ct state invalid drop
    ip protocol icmp accept
    meta l4proto ipv6-icmp accept
    tcp dport ${SSH_PORT} accept
    udp dport ${WG_PORT} accept
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
    iifname "${WG_IFACE}" oifname "${EGRESS_IFACE}" accept
    iifname "${EGRESS_IFACE}" oifname "${WG_IFACE}" ct state established,related accept
  }
}

table ip exitramp_nat {
  chain postrouting {
    type nat hook postrouting priority 100;
    ip saddr ${WG_SUBNET} oifname "${EGRESS_IFACE}" masquerade
  }
}
EOF
  systemctl enable --now nftables >/dev/null 2>&1
  nft -f /etc/nftables.conf
else
  log "SETUP_FIREWALL=no — skipping nftables (make sure NAT/masquerade is configured!)"
fi

# --- Start WireGuard --------------------------------------------------------
log "starting WireGuard (${WG_IFACE})..."
systemctl enable "wg-quick@${WG_IFACE}" >/dev/null 2>&1
if systemctl is-active --quiet "wg-quick@${WG_IFACE}"; then
  wg syncconf "$WG_IFACE" <(wg-quick strip "$WG_IFACE")
else
  systemctl start "wg-quick@${WG_IFACE}"
fi

# --- Done -------------------------------------------------------------------
PUBLIC_IP="$(curl -4 -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null || echo "<could not detect>")"

log "done."
echo
echo "  ────────────────────────────────────────────────────────"
echo "  Egress gateway is up."
echo
echo "  Static egress IP:  ${PUBLIC_IP}"
echo "  (give this IP to your vendor for allowlisting)"
echo
echo "  Next: create a config for each developer:"
echo "    sudo ./add-peer.sh <name>            # full tunnel"
echo "    sudo ./add-peer.sh <name> --split <vendor-cidrs>"
echo "  ────────────────────────────────────────────────────────"
