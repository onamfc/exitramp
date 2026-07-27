#!/usr/bin/env bash
#
# exitramp — verify your traffic is actually leaving via the gateway.
#
# Run this on your laptop (not the server) after connecting to the VPN.
#
# Usage:
#   ./check-ip.sh                 # print your current public IP
#   ./check-ip.sh 203.0.113.10    # exit 0 if it matches, 1 if not
#
set -euo pipefail

EXPECTED="${1:-}"

CURRENT="$(curl -4 -fsS --max-time 10 https://checkip.amazonaws.com)" \
  || { echo "ERROR: could not reach checkip.amazonaws.com" >&2; exit 2; }

echo "Current public IP: ${CURRENT}"

if [ -n "$EXPECTED" ]; then
  if [ "$CURRENT" = "$EXPECTED" ]; then
    echo "OK — traffic is leaving via the gateway (${EXPECTED})."
  else
    echo "MISMATCH — expected ${EXPECTED}. Is the VPN connected?" >&2
    exit 1
  fi
fi
