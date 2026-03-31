#!/usr/bin/env bash
# =============================================================================
# check_network_routes.sh
# Run on: [Jetson] or [Laptop] (auto-detects which machine it's running on)
#
# Purpose: Diagnostic script to check network connectivity between the Laptop,
#          Jetson, and Unitree GO2 main board. Prints a PASS/FAIL summary.
#
# Expected network topology:
#   Laptop  (192.168.123.100) <--ethernet--> Jetson (192.168.123.15)
#   GO2 Main Board (192.168.123.161)
#   All on the 192.168.123.0/24 subnet
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

pass()  { echo -e "  [${GREEN}PASS${NC}] $1"; }
fail()  { echo -e "  [${RED}FAIL${NC}] $1"; }
warn()  { echo -e "  [${YELLOW}WARN${NC}] $1"; }
info()  { echo -e "  [${CYAN}INFO${NC}] $1"; }
header(){ echo -e "\n${BOLD}== $1 ==${NC}"; }

# Track results for summary
declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()

record() {
    CHECK_NAMES+=("$1")
    CHECK_RESULTS+=("$2")
}

# ---------------------------------------------------------------------------
# Default IPs (from the guide). Override with environment variables if your
# setup uses different addresses:
#   JETSON_IP=192.168.123.18 LAPTOP_IP=192.168.123.50 ./check_network_routes.sh
# ---------------------------------------------------------------------------
JETSON_IP="${JETSON_IP:-192.168.123.15}"
LAPTOP_IP="${LAPTOP_IP:-192.168.123.100}"
GO2_IP="${GO2_IP:-192.168.123.161}"

# ---------------------------------------------------------------------------
# Auto-detect which machine we are running on
#   First try the configured IPs, then fall back to checking for any
#   192.168.123.x address on a local interface.
# ---------------------------------------------------------------------------
header "Machine Detection"

MY_IPS=$(ip -4 addr show | grep inet | awk '{print $2}' | cut -d/ -f1)
MACHINE="unknown"
MY_GO2_NET_IP=""

if echo "$MY_IPS" | grep -q "^${JETSON_IP}$"; then
    MACHINE="jetson"
    MY_GO2_NET_IP="$JETSON_IP"
    info "Detected: Running on the ${BOLD}Jetson${NC} ($JETSON_IP)"
elif echo "$MY_IPS" | grep -q "^${LAPTOP_IP}$"; then
    MACHINE="laptop"
    MY_GO2_NET_IP="$LAPTOP_IP"
    info "Detected: Running on the ${BOLD}Laptop${NC} ($LAPTOP_IP)"
else
    # Check if we have any 192.168.123.x address at all
    MY_GO2_NET_IP=$(echo "$MY_IPS" | grep "^192\.168\.123\." | head -1)
    if [ -n "$MY_GO2_NET_IP" ]; then
        warn "Found 192.168.123.x address ($MY_GO2_NET_IP) but it does not match"
        warn "the expected Jetson IP ($JETSON_IP) or Laptop IP ($LAPTOP_IP)."
        warn "If you used different IPs, set JETSON_IP or LAPTOP_IP env vars before running."
        info "Will run all checks using detected IP $MY_GO2_NET_IP."
    else
        warn "No 192.168.123.x address found on any local interface."
        warn "This machine may not be connected to the GO2 network yet."
        info "Will run all checks anyway."
    fi
fi

# ---------------------------------------------------------------------------
# Check 1: List all network interfaces and IPs
# ---------------------------------------------------------------------------
header "Network Interfaces"
ip -brief addr show
echo ""
record "List Interfaces" "PASS"

# ---------------------------------------------------------------------------
# Check 2: Routing table
# ---------------------------------------------------------------------------
header "Routing Table"
ip route show
echo ""
record "Routing Table" "PASS"

# ---------------------------------------------------------------------------
# Check 3: Default gateway
# ---------------------------------------------------------------------------
header "Default Gateway"
DEFAULT_GW=$(ip route show default 2>/dev/null | head -1)
if [ -n "$DEFAULT_GW" ]; then
    info "Default route: $DEFAULT_GW"
    pass "Default gateway is set"
    record "Default Gateway" "PASS"
else
    fail "No default gateway set — internet sharing may not be configured"
    record "Default Gateway" "FAIL"
fi

# ---------------------------------------------------------------------------
# Check 4: Ping GO2 main board (192.168.123.161)
# ---------------------------------------------------------------------------
header "Ping GO2 Main Board ($GO2_IP)"
if ping -c 1 "$GO2_IP" -W 3 &>/dev/null; then
    pass "GO2 main board is reachable"
    record "Ping GO2" "PASS"
else
    fail "Cannot reach GO2 main board at $GO2_IP"
    record "Ping GO2" "FAIL"
fi

# ---------------------------------------------------------------------------
# Check 5: Ping Jetson (skip if we ARE the Jetson)
# ---------------------------------------------------------------------------
header "Ping Jetson ($JETSON_IP)"
if [ "$MACHINE" == "jetson" ]; then
    info "Skipping — we are the Jetson"
    record "Ping Jetson" "PASS"
else
    if ping -c 1 "$JETSON_IP" -W 3 &>/dev/null; then
        pass "Jetson is reachable"
        record "Ping Jetson" "PASS"
    else
        fail "Cannot reach Jetson at $JETSON_IP"
        record "Ping Jetson" "FAIL"
    fi
fi

# ---------------------------------------------------------------------------
# Check 6: Ping Laptop (skip if we ARE the Laptop)
# ---------------------------------------------------------------------------
header "Ping Laptop ($LAPTOP_IP)"
if [ "$MACHINE" == "laptop" ]; then
    info "Skipping — we are the Laptop"
    record "Ping Laptop" "PASS"
else
    if ping -c 1 "$LAPTOP_IP" -W 3 &>/dev/null; then
        pass "Laptop is reachable"
        record "Ping Laptop" "PASS"
    else
        fail "Cannot reach Laptop at $LAPTOP_IP"
        record "Ping Laptop" "FAIL"
    fi
fi

# ---------------------------------------------------------------------------
# Check 7: DNS resolution
# ---------------------------------------------------------------------------
header "DNS Resolution"
DNS_OK=false

# Try nslookup first, fall back to host, fall back to getent
if command -v nslookup &>/dev/null; then
    if nslookup google.com &>/dev/null; then
        DNS_OK=true
        info "nslookup google.com succeeded"
    fi
elif command -v host &>/dev/null; then
    if host google.com &>/dev/null; then
        DNS_OK=true
        info "host google.com succeeded"
    fi
elif command -v getent &>/dev/null; then
    if getent hosts google.com &>/dev/null; then
        DNS_OK=true
        info "getent hosts google.com succeeded"
    fi
else
    warn "No DNS lookup tool found (nslookup, host, or getent)"
fi

if $DNS_OK; then
    pass "DNS resolution works"
    record "DNS Resolution" "PASS"
else
    fail "DNS resolution failed — check DNS config with: resolvectl status"
    # Show current DNS config for debugging
    if command -v resolvectl &>/dev/null; then
        info "Current DNS configuration:"
        resolvectl status 2>/dev/null | grep -A2 "DNS Servers" | sed 's/^/    /'
    elif [ -f /etc/resolv.conf ]; then
        info "Current /etc/resolv.conf:"
        grep -v '^#' /etc/resolv.conf | grep -v '^$' | sed 's/^/    /'
    fi
    record "DNS Resolution" "FAIL"
fi

# ---------------------------------------------------------------------------
# Check 8: Internet connectivity
# ---------------------------------------------------------------------------
header "Internet Connectivity"
if ping -c 1 8.8.8.8 -W 3 &>/dev/null; then
    pass "Internet reachable (ping 8.8.8.8)"
    record "Internet" "PASS"
else
    fail "Cannot reach 8.8.8.8 — no internet"
    if [ "$MACHINE" == "jetson" ]; then
        info "If sharing internet from laptop, make sure:"
        info "  1. Laptop is running share_internet_from_laptop.sh"
        info "  2. Default gateway is set: sudo nmcli con mod go2-network ipv4.gateway $LAPTOP_IP && sudo nmcli con up go2-network"
        info "  3. DNS is set: sudo nmcli con mod go2-network ipv4.dns '8.8.8.8 8.8.4.4' && sudo nmcli con up go2-network"
    fi
    record "Internet" "FAIL"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
header "Summary"
echo ""
printf "  %-25s %s\n" "CHECK" "RESULT"
printf "  %-25s %s\n" "-------------------------" "------"

TOTAL=${#CHECK_NAMES[@]}
PASSES=0
FAILS=0

for i in "${!CHECK_NAMES[@]}"; do
    NAME="${CHECK_NAMES[$i]}"
    RESULT="${CHECK_RESULTS[$i]}"
    case "$RESULT" in
        PASS) COLOR="$GREEN"; ((PASSES++)) ;;
        FAIL) COLOR="$RED";   ((FAILS++))  ;;
        *)    COLOR="$NC" ;;
    esac
    printf "  %-25s ${COLOR}%s${NC}\n" "$NAME" "$RESULT"
done

echo ""
echo -e "  ${GREEN}$PASSES passed${NC}, ${RED}$FAILS failed${NC} out of $TOTAL checks."
echo ""

if [ "$FAILS" -gt 0 ]; then
    echo -e "  ${RED}Some checks failed. Review the output above.${NC}"
    exit 1
else
    echo -e "  ${GREEN}All network checks passed!${NC}"
    exit 0
fi
