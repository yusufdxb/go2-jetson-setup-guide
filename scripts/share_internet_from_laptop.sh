#!/usr/bin/env bash
# =============================================================================
# share_internet_from_laptop.sh
# Run on: [Laptop]
#
# Purpose: Set up NAT internet sharing from your laptop to the Jetson.
#          The laptop acts as a router: it forwards traffic from the Jetson
#          (connected via Ethernet) out through its internet-facing interface
#          (typically Wi-Fi).
#
# Usage:
#   sudo ./share_internet_from_laptop.sh <internet_iface> <jetson_iface>
#   sudo ./share_internet_from_laptop.sh --clean <internet_iface> <jetson_iface>
#
# Examples:
#   sudo ./share_internet_from_laptop.sh wlan0 eth0        # Set up sharing
#   sudo ./share_internet_from_laptop.sh --clean wlan0 eth0 # Remove rules
# =============================================================================
set -e

# ---------------------------------------------------------------------------
# Color helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()   { echo -e "${RED}[ERR ]${NC} $1"; }

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage:"
    echo "  sudo $0 <internet_iface> <jetson_iface>"
    echo "  sudo $0 --clean <internet_iface> <jetson_iface>"
    echo ""
    echo "Arguments:"
    echo "  internet_iface   Interface with internet access (e.g., wlan0)"
    echo "  jetson_iface     Interface connected to the Jetson (e.g., eth0)"
    echo "  --clean          Remove the NAT rules instead of adding them"
    echo ""
    echo "Available interfaces:"
    ip -brief link show | awk '{print "  " $1 " (" $2 ")"}'
    exit 1
}

# ---------------------------------------------------------------------------
# Prerequisite: must run as root
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (use sudo)."
    usage
fi

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CLEAN=false

if [ "$1" == "--clean" ]; then
    CLEAN=true
    shift
fi

if [ $# -lt 2 ]; then
    err "Missing arguments."
    usage
fi

INET_IFACE="$1"   # Interface with internet (e.g., wlan0)
JETSON_IFACE="$2"  # Interface to Jetson (e.g., eth0)

# ---------------------------------------------------------------------------
# Validate that the specified interfaces exist
# ---------------------------------------------------------------------------
if ! ip link show "$INET_IFACE" &>/dev/null; then
    err "Interface '$INET_IFACE' does not exist."
    echo ""
    echo "Available interfaces:"
    ip -brief link show | awk '{print "  " $1}'
    exit 1
fi

if ! ip link show "$JETSON_IFACE" &>/dev/null; then
    err "Interface '$JETSON_IFACE' does not exist."
    echo ""
    echo "Available interfaces:"
    ip -brief link show | awk '{print "  " $1}'
    exit 1
fi

# ---------------------------------------------------------------------------
# Clean mode: remove the NAT rules
# ---------------------------------------------------------------------------
if $CLEAN; then
    echo -e "\n${BOLD}== Removing NAT Internet Sharing ==${NC}\n"

    info "Removing iptables MASQUERADE rule..."
    iptables -t nat -D POSTROUTING -o "$INET_IFACE" -j MASQUERADE 2>/dev/null && \
        ok "MASQUERADE rule removed" || warn "MASQUERADE rule was not present"

    info "Removing iptables FORWARD rules..."
    iptables -D FORWARD -i "$JETSON_IFACE" -o "$INET_IFACE" -j ACCEPT 2>/dev/null && \
        ok "Forward rule (Jetson -> Internet) removed" || warn "Rule was not present"
    iptables -D FORWARD -i "$INET_IFACE" -o "$JETSON_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null && \
        ok "Forward rule (Internet -> Jetson, established) removed" || warn "Rule was not present"

    # Restore IP forwarding to disabled (safe default)
    info "Disabling IP forwarding..."
    sysctl -w net.ipv4.ip_forward=0 >/dev/null
    ok "IP forwarding disabled"

    echo ""
    ok "NAT rules cleaned up."
    echo ""
    exit 0
fi

# ---------------------------------------------------------------------------
# Setup mode: configure NAT internet sharing
# ---------------------------------------------------------------------------
echo -e "\n${BOLD}== Setting Up NAT Internet Sharing ==${NC}\n"
info "Internet interface : $INET_IFACE"
info "Jetson interface   : $JETSON_IFACE"
echo ""

# Step 1: Enable IP forwarding
#   This tells the kernel to route packets between interfaces.
info "Enabling IP forwarding..."
# Back up the current setting so user knows what it was
CURRENT_FWD=$(sysctl -n net.ipv4.ip_forward)
if [ "$CURRENT_FWD" -eq 1 ]; then
    ok "IP forwarding was already enabled"
else
    sysctl -w net.ipv4.ip_forward=1 >/dev/null
    ok "IP forwarding enabled (was: $CURRENT_FWD)"
fi

# Step 2: Set up iptables MASQUERADE
#   MASQUERADE rewrites the source address of outgoing packets so they
#   appear to come from the laptop. This is standard NAT.
info "Adding iptables MASQUERADE rule on $INET_IFACE..."

# Avoid adding duplicate rules — check if it already exists
if iptables -t nat -C POSTROUTING -o "$INET_IFACE" -j MASQUERADE 2>/dev/null; then
    ok "MASQUERADE rule already exists — skipping"
else
    iptables -t nat -A POSTROUTING -o "$INET_IFACE" -j MASQUERADE
    ok "MASQUERADE rule added"
fi

# Step 3: Allow forwarding between the two interfaces
info "Adding iptables FORWARD rules..."

# Allow traffic from Jetson interface to internet interface
if iptables -C FORWARD -i "$JETSON_IFACE" -o "$INET_IFACE" -j ACCEPT 2>/dev/null; then
    ok "Forward rule (Jetson -> Internet) already exists"
else
    iptables -A FORWARD -i "$JETSON_IFACE" -o "$INET_IFACE" -j ACCEPT
    ok "Forward rule (Jetson -> Internet) added"
fi

# Allow return traffic (established connections) from internet to Jetson
if iptables -C FORWARD -i "$INET_IFACE" -o "$JETSON_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
    ok "Forward rule (Internet -> Jetson, established) already exists"
else
    iptables -A FORWARD -i "$INET_IFACE" -o "$JETSON_IFACE" -m state --state RELATED,ESTABLISHED -j ACCEPT
    ok "Forward rule (Internet -> Jetson, established) added"
fi

# ---------------------------------------------------------------------------
# Print what was configured
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}== Configuration Complete ==${NC}"
echo ""

# Get the laptop's IP on the Jetson-facing interface
LAPTOP_IP=$(ip -4 addr show "$JETSON_IFACE" 2>/dev/null | grep inet | awk '{print $2}' | cut -d/ -f1 | head -1)

if [ -z "$LAPTOP_IP" ]; then
    warn "No IP address set on $JETSON_IFACE yet."
    warn "You may need to assign one, e.g.:"
    echo -e "    ${CYAN}sudo ip addr add 192.168.123.100/24 dev $JETSON_IFACE${NC}"
    LAPTOP_IP="<laptop-ip-on-$JETSON_IFACE>"
fi

info "Laptop is sharing internet from $INET_IFACE through $JETSON_IFACE"
echo ""

# ---------------------------------------------------------------------------
# Print commands for the Jetson side
# ---------------------------------------------------------------------------
echo -e "${BOLD}== Commands to Run on the Jetson ==${NC}"
echo ""
echo "  Run these on the Jetson to route its traffic through this laptop:"
echo ""
echo -e "  ${GREEN}# Set the laptop as the default gateway${NC}"
echo -e "  ${CYAN}sudo ip route add default via $LAPTOP_IP${NC}"
echo ""
echo -e "  ${GREEN}# Set DNS (Google's public DNS)${NC}"
echo -e "  ${CYAN}echo 'nameserver 8.8.8.8' | sudo tee /etc/resolv.conf${NC}"
echo ""
echo -e "  ${GREEN}# Test internet connectivity${NC}"
echo -e "  ${CYAN}ping -c 3 8.8.8.8${NC}"
echo -e "  ${CYAN}ping -c 3 google.com${NC}"
echo ""

# ---------------------------------------------------------------------------
# Persistence warning
# ---------------------------------------------------------------------------
warn "These iptables rules are NOT persistent across reboots."
warn "To remove them, run:"
echo -e "    ${CYAN}sudo $0 --clean $INET_IFACE $JETSON_IFACE${NC}"
echo ""
