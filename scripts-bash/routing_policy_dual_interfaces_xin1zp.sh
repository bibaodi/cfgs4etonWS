#!/bin/bash
# Script: setup_routing_policy.sh
# Purpose: Configure Linux routing with:
#   - Default via wlp3s0 (metric 100)
#   - Local subnet 192.168.0.0/24 via eth0
#   - Backup default via eth0 (metric 700)

set -e  # Exit on error

# --- Configuration ---
WIFI_IF="wlp3s0"
ETH_IF="eth0"
WIFI_GW="192.168.178.254"
ETH_GW="192.168.0.1"
WIFI_SRC="192.168.178.196"
ETH_SRC="192.168.0.138"
LOCAL_SUBNET="192.168.0.0/24"

# --- Helper: flush existing default routes to avoid conflicts ---
echo "Cleaning up old default routes..."
ip route del default 2>/dev/null || true

# --- Add primary default via Wi-Fi (metric 100) ---
echo "Adding primary default route via $WIFI_IF (metric 100)"
ip route replace default via $WIFI_GW dev $WIFI_IF src $WIFI_SRC metric 100

# --- Add backup default via Ethernet (metric 700) ---
echo "Adding backup default route via $ETH_IF (metric 700)"
ip route replace default via $ETH_GW dev $ETH_IF metric 700

# --- Ensure local subnet traffic uses Ethernet (more specific route) ---
echo "Adding route for $LOCAL_SUBNET via $ETH_IF (metric 100)"
ip route replace $LOCAL_SUBNET dev $ETH_IF src $ETH_SRC metric 100

# --- Optional: Verifications ---
echo ""
echo "Current routing table (relevant entries):"
ip route show | grep -E "default|192.168.0.0"

# --- Show which default is active ---
ACTIVE_DEFAULT=$(ip route show default | head -1)
echo ""
echo "Active default route: $ACTIVE_DEFAULT"
echo "Internet traffic will use the route with the lowest metric (100 → $WIFI_IF)"
echo "If $WIFI_IF fails, the kernel automatically switches to metric 700 ($ETH_IF)"

:<<'comment'
$ ip route show
default via 192.168.178.254 dev wlp3s0 src 192.168.178.196 metric 100
default via 192.168.0.1 dev eth0 metric 700
172.16.233.0/24 dev vmnet1 proto kernel scope link src 172.16.233.1
172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1 linkdown
192.168.0.0/24 dev eth0 scope link src 192.168.0.138 metric 100
192.168.0.0/16 dev eth0 scope link metric 100
192.168.168.0/24 dev vmnet8 proto kernel scope link src 192.168.168.1
192.168.178.0/24 dev wlp3s0 proto kernel scope link src 192.168.178.196 metric 600
comment


