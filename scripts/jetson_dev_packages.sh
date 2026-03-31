#!/usr/bin/env bash
# =============================================================================
# jetson_dev_packages.sh
# Run on: [Jetson]
#
# Purpose: Install common development packages needed for GO2 robotics
#          development on the Jetson Orin NX/Nano.
#
# Installs:
#   - Build tools: build-essential, cmake, git, curl, wget
#   - Python:      python3-pip, python3-venv
#   - Utilities:   htop, net-tools, nano, vim
#   - Robotics:    libeigen3-dev, libopencv-dev
#   - Jetson:      jetson-stats (jtop) via pip
#
# Note: ROS 2 is NOT installed by this script.
#       See docs/06-ros2-bootstrap.md for ROS 2 setup instructions.
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
# Prerequisite: must run as root
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    err "This script must be run as root (use sudo)."
    echo "  Usage: sudo ./jetson_dev_packages.sh"
    exit 1
fi

echo -e "\n${BOLD}== Jetson Development Packages Setup ==${NC}\n"

# ---------------------------------------------------------------------------
# Step 1: Update apt package lists
#   Always update before installing to make sure we get the latest versions
#   and avoid broken dependencies.
# ---------------------------------------------------------------------------
info "Updating apt package lists..."
apt-get update -qq
ok "Package lists updated"

# ---------------------------------------------------------------------------
# Step 2: Define the list of apt packages to install
# ---------------------------------------------------------------------------
APT_PACKAGES=(
    # Build tools — compiler, build system, version control
    build-essential    # gcc, g++, make, etc.
    cmake              # Cross-platform build system (used by most robotics projects)
    git                # Version control
    curl               # HTTP client (useful for downloading scripts/APIs)
    wget               # HTTP downloader (useful for fetching files)

    # Python — needed for many robotics tools and scripts
    python3-pip        # Python package manager
    python3-venv       # Python virtual environments (best practice for isolation)

    # System utilities
    htop               # Interactive process viewer (better than top)
    net-tools          # ifconfig, netstat, etc. (useful for network debugging)
    nano               # Simple text editor
    vim                # Powerful text editor

    # Robotics libraries
    libeigen3-dev      # Linear algebra library (used by nearly all robotics software)
    libopencv-dev      # OpenCV computer vision library (useful for camera/vision work)
)

# ---------------------------------------------------------------------------
# Step 3: Install all apt packages in a single call
#   Using a single apt-get install is faster and handles dependencies better
#   than installing one at a time.
# ---------------------------------------------------------------------------
info "Installing apt packages..."
echo ""
info "Packages: ${APT_PACKAGES[*]}"
echo ""

apt-get install -y "${APT_PACKAGES[@]}"

ok "All apt packages installed"

# ---------------------------------------------------------------------------
# Step 4: Install pip packages
#   jetson-stats provides the 'jtop' command — a GPU/system monitor built
#   specifically for Jetson. It shows GPU usage, temperatures, power draw, etc.
# ---------------------------------------------------------------------------
echo ""
info "Installing Python packages via pip..."

# Install jetson-stats (jtop)
if command -v jtop &>/dev/null; then
    ok "jetson-stats (jtop) is already installed"
else
    info "Installing jetson-stats..."
    pip3 install jetson-stats
    ok "jetson-stats installed"
fi

# ---------------------------------------------------------------------------
# Step 5: Print summary of what was installed
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}== Installation Summary ==${NC}"
echo ""

# Verify key tools are available
declare -a TOOLS=("gcc" "cmake" "git" "python3" "pip3" "htop" "nano" "vim")

for TOOL in "${TOOLS[@]}"; do
    if command -v "$TOOL" &>/dev/null; then
        VERSION=$("$TOOL" --version 2>/dev/null | head -1 || echo "installed")
        ok "$TOOL — $VERSION"
    else
        warn "$TOOL — not found on PATH"
    fi
done

# Check Eigen
if [ -f /usr/include/eigen3/Eigen/Core ]; then
    ok "Eigen3 — headers found at /usr/include/eigen3/"
else
    warn "Eigen3 — headers not found"
fi

# Check OpenCV
if pkg-config --modversion opencv4 2>/dev/null; then
    CV_VER=$(pkg-config --modversion opencv4)
    ok "OpenCV — version $CV_VER"
elif pkg-config --modversion opencv 2>/dev/null; then
    CV_VER=$(pkg-config --modversion opencv)
    ok "OpenCV — version $CV_VER"
else
    warn "OpenCV — pkg-config entry not found (may still be installed)"
fi

# Check jtop
if command -v jtop &>/dev/null; then
    ok "jtop — installed"
else
    warn "jtop — not found (you may need to restart your shell or reboot)"
fi

# ---------------------------------------------------------------------------
# ROS 2 note
# ---------------------------------------------------------------------------
echo ""
echo -e "${YELLOW}NOTE:${NC} ROS 2 is ${BOLD}not${NC} installed by this script."
echo "  For ROS 2 setup, see: docs/06-ros2-bootstrap.md"
echo ""

# ---------------------------------------------------------------------------
# Suggest next steps
# ---------------------------------------------------------------------------
echo -e "${BOLD}== Next Steps ==${NC}"
echo ""
echo "  1. Verify everything with the health check script:"
echo -e "     ${CYAN}sudo ./jetson_first_boot_check.sh${NC}"
echo ""
echo "  2. If you just installed jetson-stats for the first time,"
echo "     you may need to reboot before jtop works:"
echo -e "     ${CYAN}sudo reboot${NC}"
echo ""
ok "Development environment setup complete!"
echo ""
