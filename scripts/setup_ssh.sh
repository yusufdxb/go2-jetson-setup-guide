#!/usr/bin/env bash
# =============================================================================
# setup_ssh.sh
# Run on: [Jetson]
#
# Purpose: Ensure SSH is properly configured on the Jetson so you can connect
#          from your laptop. Installs openssh-server if missing, enables the
#          service, opens the firewall, and prints connection info.
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
# Prerequisite: must run as root or with sudo
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (use sudo)."
    echo "  Usage: sudo ./setup_ssh.sh"
    exit 1
fi

echo -e "\n${BOLD}== SSH Setup for Jetson ==${NC}\n"

# ---------------------------------------------------------------------------
# Step 1: Install openssh-server if not already present
# ---------------------------------------------------------------------------
info "Checking if openssh-server is installed..."
if dpkg -l openssh-server 2>/dev/null | grep -q "^ii"; then
    ok "openssh-server is already installed"
else
    info "Installing openssh-server..."
    apt-get update -qq
    apt-get install -y openssh-server
    ok "openssh-server installed"
fi

# ---------------------------------------------------------------------------
# Step 2: Generate host keys if missing
#   SSH won't start without host keys. They are usually generated at install
#   time, but if someone deleted them we regenerate.
# ---------------------------------------------------------------------------
info "Checking SSH host keys..."
KEYS_MISSING=false
for KEYTYPE in rsa ecdsa ed25519; do
    if [ ! -f "/etc/ssh/ssh_host_${KEYTYPE}_key" ]; then
        warn "Missing host key: ssh_host_${KEYTYPE}_key — generating..."
        ssh-keygen -t "$KEYTYPE" -f "/etc/ssh/ssh_host_${KEYTYPE}_key" -N "" -q
        KEYS_MISSING=true
    fi
done

if $KEYS_MISSING; then
    ok "Missing host keys regenerated"
else
    ok "All host keys present"
fi

# ---------------------------------------------------------------------------
# Step 3: Enable and start the SSH service
# ---------------------------------------------------------------------------
info "Enabling and starting SSH service..."

# The service is called "ssh" on Ubuntu (not "sshd")
systemctl enable ssh --now 2>/dev/null || systemctl enable sshd --now 2>/dev/null

if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    ok "SSH service is running"
else
    err "SSH service failed to start — check 'systemctl status ssh' for details"
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 4: Open firewall if ufw is active
#   We only touch ufw if it's actively running. If it's not installed or not
#   active, we skip — no need to install a firewall just for this.
# ---------------------------------------------------------------------------
info "Checking firewall (ufw)..."
if command -v ufw &>/dev/null; then
    UFW_STATUS=$(ufw status | head -1)
    if echo "$UFW_STATUS" | grep -q "active"; then
        info "ufw is active — allowing SSH (port 22)..."
        ufw allow ssh
        ok "SSH allowed through ufw"
    else
        ok "ufw is installed but not active — no firewall rule needed"
    fi
else
    ok "ufw is not installed — no firewall to configure"
fi

# ---------------------------------------------------------------------------
# Step 5: Print connection info
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}== Connection Info ==${NC}"
echo ""

# Gather all non-loopback IPv4 addresses
info "Jetson IP addresses:"
ip -4 addr show | grep inet | grep -v '127.0.0.1' | while read -r line; do
    IFACE=$(echo "$line" | awk '{print $NF}')
    ADDR=$(echo "$line" | awk '{print $2}' | cut -d/ -f1)
    echo -e "    ${CYAN}$IFACE${NC}: $ADDR"
done

CURRENT_USER=${SUDO_USER:-$(whoami)}
echo ""
info "To connect from your laptop, run:"
echo ""

# Print an example for each IP
ip -4 addr show | grep inet | grep -v '127.0.0.1' | while read -r line; do
    ADDR=$(echo "$line" | awk '{print $2}' | cut -d/ -f1)
    echo -e "    ${GREEN}ssh ${CURRENT_USER}@${ADDR}${NC}"
done

echo ""
info "SSH is configured. You can now connect from your laptop."
echo ""
