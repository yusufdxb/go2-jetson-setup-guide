#!/usr/bin/env bash
# =============================================================================
# jetson_first_boot_check.sh
# Run on: [Jetson]
#
# Purpose: Verify the Jetson Orin NX/Nano is healthy after first boot.
#          Checks OS, GPU, CUDA, JetPack, disk, RAM, network, and SSH.
#          Prints a PASS/FAIL summary at the end.
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
NC='\033[0m' # No Color

pass()  { echo -e "  [${GREEN}PASS${NC}] $1"; }
fail()  { echo -e "  [${RED}FAIL${NC}] $1"; }
warn()  { echo -e "  [${YELLOW}WARN${NC}] $1"; }
info()  { echo -e "  [${CYAN}INFO${NC}] $1"; }
header(){ echo -e "\n${BOLD}== $1 ==${NC}"; }

# We'll track results so we can print a summary table at the end.
declare -a CHECK_NAMES=()
declare -a CHECK_RESULTS=()   # PASS, FAIL, or WARN

record() {
    # Usage: record "Check Name" PASS|FAIL|WARN
    CHECK_NAMES+=("$1")
    CHECK_RESULTS+=("$2")
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

header "Jetson First-Boot Health Check"
echo "Running on: $(hostname) at $(date)"

# 1. OS Version ---------------------------------------------------------
header "OS Version"
if [ -f /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    info "OS: $PRETTY_NAME"
    if [[ "$VERSION_ID" == "22.04" ]]; then
        pass "Ubuntu 22.04 detected"
        record "OS Version (22.04)" "PASS"
    else
        warn "Expected Ubuntu 22.04, got $VERSION_ID"
        record "OS Version (22.04)" "WARN"
    fi
else
    fail "Cannot read /etc/os-release"
    record "OS Version (22.04)" "FAIL"
fi

# 2. Kernel Version -----------------------------------------------------
header "Kernel Version"
KERNEL=$(uname -r)
info "Kernel: $KERNEL"
# Jetson kernels are typically 5.10 or 5.15 for JetPack 5.x/6.x
record "Kernel" "PASS"
pass "Kernel version reported"

# 3. JetPack Version ----------------------------------------------------
header "JetPack Version"
JETPACK_FOUND=false

# Method 1: apt package
if apt list --installed 2>/dev/null | grep -q nvidia-jetpack; then
    JP_VER=$(apt list --installed 2>/dev/null | grep nvidia-jetpack | awk '{print $2}')
    info "JetPack (apt): $JP_VER"
    JETPACK_FOUND=true
fi

# Method 2: /etc/nv_tegra_release
if [ -f /etc/nv_tegra_release ]; then
    NV_REL=$(cat /etc/nv_tegra_release)
    info "Tegra release: $NV_REL"
    JETPACK_FOUND=true
fi

if $JETPACK_FOUND; then
    pass "JetPack information found"
    record "JetPack Version" "PASS"
else
    fail "Could not determine JetPack version"
    record "JetPack Version" "FAIL"
fi

# 4. CUDA ----------------------------------------------------------------
header "CUDA"
if command -v nvcc &>/dev/null; then
    CUDA_VER=$(nvcc --version | grep "release" | awk '{print $6}' | tr -d ',')
    info "CUDA: $CUDA_VER"
    pass "nvcc found"
    record "CUDA" "PASS"
else
    # nvcc may not be on PATH — check common install locations
    if [ -f /usr/local/cuda/bin/nvcc ]; then
        CUDA_VER=$(/usr/local/cuda/bin/nvcc --version | grep "release" | awk '{print $6}' | tr -d ',')
        info "CUDA: $CUDA_VER (found at /usr/local/cuda/bin/nvcc)"
        warn "nvcc is not on PATH — add /usr/local/cuda/bin to your PATH"
        record "CUDA" "WARN"
    else
        fail "nvcc not found"
        record "CUDA" "FAIL"
    fi
fi

# 5. GPU Detected --------------------------------------------------------
header "GPU"
GPU_OK=false

# On Jetson, nvidia-smi is usually NOT available (it's for dGPUs).
# Instead, check for Jetson-specific GPU device nodes.
if [ -e /dev/nvhost-gpu ] || [ -e /dev/nvgpu/igpu0/as ]; then
    info "Jetson GPU device node found"
    GPU_OK=true
fi

# Also try nvidia-smi just in case (Orin sometimes has it)
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null && GPU_OK=true
fi

if $GPU_OK; then
    pass "GPU detected"
    record "GPU Detected" "PASS"
else
    fail "GPU not detected — check your JetPack installation"
    record "GPU Detected" "FAIL"
fi

# 6. Disk Space ----------------------------------------------------------
header "Disk Space"
DISK_LINE=$(df -h / | tail -1)
DISK_AVAIL=$(echo "$DISK_LINE" | awk '{print $4}')
DISK_USE_PCT=$(echo "$DISK_LINE" | awk '{print $5}' | tr -d '%')
info "Root filesystem: $DISK_AVAIL available (${DISK_USE_PCT}% used)"

if [ "$DISK_USE_PCT" -lt 90 ]; then
    pass "Disk usage under 90%"
    record "Disk Space" "PASS"
else
    fail "Disk usage at ${DISK_USE_PCT}% — consider freeing space"
    record "Disk Space" "FAIL"
fi

# 7. RAM -----------------------------------------------------------------
header "RAM"
free -h | head -2
TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MB=$((TOTAL_KB / 1024))
info "Total RAM: ${TOTAL_MB} MB"

if [ "$TOTAL_MB" -ge 7000 ]; then
    pass "RAM >= 7 GB (likely 8 GB or 16 GB module)"
    record "RAM" "PASS"
else
    warn "RAM is ${TOTAL_MB} MB — Jetson Orin NX/Nano usually has 8 or 16 GB"
    record "RAM" "WARN"
fi

# 8. Network Interfaces --------------------------------------------------
header "Network Interfaces"
ip -brief addr show
record "Network Interfaces" "PASS"
pass "Network interfaces listed above"

# 9. SSH Server ----------------------------------------------------------
header "SSH Server"
if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
    pass "SSH server is running"
    record "SSH Server" "PASS"
else
    fail "SSH server is NOT running — run setup_ssh.sh to fix"
    record "SSH Server" "FAIL"
fi

# 10. Internet Connectivity ----------------------------------------------
header "Internet Connectivity"
if ping -c 1 8.8.8.8 -W 3 &>/dev/null; then
    pass "Internet reachable (ping 8.8.8.8)"
    record "Internet" "PASS"
else
    fail "Cannot reach 8.8.8.8 — no internet connectivity"
    record "Internet" "FAIL"
fi

# 11. jtop ---------------------------------------------------------------
header "jtop (jetson-stats)"
if command -v jtop &>/dev/null; then
    pass "jtop is installed"
    record "jtop Installed" "PASS"
else
    warn "jtop not found — install with: sudo pip3 install jetson-stats"
    record "jtop Installed" "WARN"
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
WARNS=0

for i in "${!CHECK_NAMES[@]}"; do
    NAME="${CHECK_NAMES[$i]}"
    RESULT="${CHECK_RESULTS[$i]}"
    case "$RESULT" in
        PASS) COLOR="$GREEN"; ((PASSES++)) ;;
        FAIL) COLOR="$RED";   ((FAILS++))  ;;
        WARN) COLOR="$YELLOW"; ((WARNS++)) ;;
        *)    COLOR="$NC" ;;
    esac
    printf "  %-25s ${COLOR}%s${NC}\n" "$NAME" "$RESULT"
done

echo ""
echo -e "  ${GREEN}$PASSES passed${NC}, ${RED}$FAILS failed${NC}, ${YELLOW}$WARNS warnings${NC} out of $TOTAL checks."
echo ""

if [ "$FAILS" -gt 0 ]; then
    echo -e "  ${RED}Some checks failed. Review the output above for details.${NC}"
    exit 1
else
    echo -e "  ${GREEN}Jetson looks healthy!${NC}"
    exit 0
fi
