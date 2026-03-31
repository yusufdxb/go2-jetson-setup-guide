# Unitree GO2 + Jetson Orin Setup Guide

**Get your NVIDIA Jetson Orin NX / Orin Nano running on a Unitree GO2 quadruped robot -- from first boot to ROS 2.**

---

## Who This Is For

You have physically mounted a Jetson Orin NX or Jetson Orin Nano inside (or on top of) your Unitree GO2. The board is wired for power and connected to the GO2's internal Ethernet network. Now you are staring at it wondering: *what next?*

This guide walks you through flashing the Jetson, getting on the network, sharing internet from your laptop, installing ROS 2, and talking to the GO2 -- step by step, with exact commands.

No prior Jetson or ROS experience is assumed. If you can open a terminal and type commands, you can follow this guide.

---

## Support Matrix

This guide targets one specific, tested configuration. Other combinations may work but are not covered here.

| Component | This Guide | Notes |
|-----------|-----------|-------|
| **Jetson module** | Orin NX 16 GB or Orin Nano 8 GB | Both use the same carrier board form factor |
| **JetPack** | **6.x (latest)** | Provides Ubuntu 22.04 and CUDA 12.x |
| **Host OS (Jetson)** | Ubuntu 22.04 (Jammy) | Comes with JetPack 6.x |
| **ROS 2** | Humble Hawksbill (LTS) | Binary install from apt; requires Ubuntu 22.04 |
| **GO2 model** | EDU (tested) | PRO may work — see [docs/07-go2-notes.md](docs/07-go2-notes.md) |
| **Host laptop** | Ubuntu 22.04 recommended | Ubuntu 20.04 also works for flashing |

**If you are using JetPack 5.x:** JetPack 5.x supports Orin modules (from 5.0.2+) and runs Ubuntu 20.04. On Ubuntu 20.04, ROS 2 Humble binaries are not available from apt; you would need ROS 2 Galactic or build Humble from source. This guide does not cover the JetPack 5.x path. Upgrading to JetPack 6.x is strongly recommended for new setups.

---

## What's Covered

- Flashing JetPack OS onto the Jetson
- First-boot configuration and headless access
- Connecting the Jetson to the GO2's internal 192.168.123.x network
- Sharing your laptop's internet connection with the Jetson
- Installing and bootstrapping ROS 2 (Humble)
- GO2-specific networking notes and quirks
- Troubleshooting common issues
- Helper scripts to automate repetitive tasks

---

## Prerequisites

### Hardware

- Unitree GO2 (EDU or PRO) quadruped robot
- NVIDIA Jetson Orin NX or Jetson Orin Nano (developer kit or module + carrier board)
- The Jetson physically installed inside/on the GO2 with power and Ethernet connected
- A laptop or desktop computer (Ubuntu 20.04 or 22.04 recommended) with:
  - A USB-C cable for flashing (USB-C to USB-A is fine)
  - An Ethernet port or USB-to-Ethernet adapter
  - Wi-Fi (so you can share internet to the Jetson)
- MicroSD card (if your Jetson variant boots from SD) or NVMe SSD
- A monitor + keyboard for initial setup (optional if you configure headless)

### Software

- NVIDIA SDK Manager installed on your laptop (download from [developer.nvidia.com](https://developer.nvidia.com/sdk-manager))
- Ubuntu 20.04 or 22.04 on your host machine (required by SDK Manager)
- Basic familiarity with the Linux terminal

---

## Quick Start (Fast Path)

For experienced users who just want the condensed steps:

1. **Flash JetPack 6.x** onto the Jetson using NVIDIA SDK Manager from your laptop.
2. **Boot the Jetson** and complete the OEM setup (user account, locale, etc.).
3. **Connect via Ethernet** -- plug the Jetson into the GO2's internal network switch.
4. **Assign a static IP** on the Jetson's Ethernet interface in the `192.168.123.x` range (e.g., `192.168.123.15`).

   ```bash
   # [Jetson] Set static IP via nmcli (no gateway needed yet — that comes in the internet-sharing step)
   sudo nmcli con add type ethernet ifname eth0 con-name go2-network \
     ip4 192.168.123.15/24
   sudo nmcli con up go2-network
   ```

   > Replace `eth0` with your actual Ethernet interface name (check with `ip link show`).

5. **SSH into the Jetson from your laptop:**

   ```bash
   # [Laptop]
   ssh user@192.168.123.15
   ```

6. **Share internet** from your laptop to the Jetson by enabling IP forwarding and NAT on the laptop's Ethernet interface. See [docs/05-internet-sharing.md](docs/05-internet-sharing.md).
7. **Update packages:**

   ```bash
   # [Jetson]
   sudo apt update && sudo apt upgrade -y
   ```

8. **Install ROS 2 Humble** following the step-by-step instructions in [docs/06-ros2-bootstrap.md](docs/06-ros2-bootstrap.md).

9. **Verify connectivity to the GO2** head unit at `192.168.123.161`:

   ```bash
   # [Jetson]
   ping 192.168.123.161
   ```

10. **Verify ROS 2 is working** with the built-in demo nodes (not GO2-specific topics yet):

    ```bash
    # [Jetson]
    source /opt/ros/humble/setup.bash
    ros2 run demo_nodes_cpp talker
    ```

    > **Note:** Seeing GO2 robot topics requires the Unitree SDK or `unitree_ros2` package in addition to ROS 2. See [docs/07-go2-notes.md](docs/07-go2-notes.md).

For the full explanation behind each step, read on.

---

## Full Step-by-Step Guide

Work through these guides in order. Each one builds on the previous.

| Step | Guide | Description |
|------|-------|-------------|
| 1 | [Hardware Overview](docs/01-hardware-overview.md) | Physical layout, power wiring, port identification |
| 2 | [Flash the Jetson](docs/02-flash-jetson.md) | Using SDK Manager to flash JetPack onto the Jetson |
| 3 | [First Boot](docs/03-first-boot.md) | OEM setup, user creation, initial system configuration |
| 4 | [Networking and SSH](docs/04-networking-and-ssh.md) | Static IP setup, SSH access, key-based authentication |
| 5 | [Internet Sharing](docs/05-internet-sharing.md) | Sharing your laptop's Wi-Fi with the Jetson over Ethernet |
| 6 | [ROS 2 Bootstrap](docs/06-ros2-bootstrap.md) | Installing ROS 2 Humble, setting up workspaces |
| 7 | [GO2 Notes](docs/07-go2-notes.md) | GO2-specific IPs, services, known quirks |
| 8 | [Troubleshooting](docs/08-troubleshooting.md) | Common problems and solutions |

---

## Helper Scripts

All scripts are in the `scripts/` directory. Run them from the repository root.

| Script | Run On | Description |
|--------|--------|-------------|
| `scripts/share_internet_from_laptop.sh` | Laptop | Enables NAT and IP forwarding to share internet with the Jetson. Run with `--clean` to remove rules. |
| `scripts/setup_ssh.sh` | Jetson | Installs openssh-server, enables the service, opens the firewall. |
| `scripts/jetson_first_boot_check.sh` | Jetson | Verifies OS, CUDA, GPU, disk, RAM, SSH, and internet. Prints a PASS/FAIL summary. |
| `scripts/jetson_dev_packages.sh` | Jetson | Installs common development packages (build tools, Python, OpenCV, Eigen, jtop). |
| `scripts/check_network_routes.sh` | Jetson or Laptop | Checks connectivity to the GO2, Jetson, and internet. Auto-detects which machine it runs on. |

Before running any script, make it executable:

```bash
chmod +x scripts/<script-name>.sh
```

---

## Common Network Layout

Below is the typical network topology when the Jetson is installed on the GO2 and your laptop is connected for development.

```
                   Wi-Fi (internet)
                        |
                   +---------+
                   | Laptop  |
                   | .123.100|
                   +---------+
                        |
                    Ethernet
                   (192.168.123.x)
                        |
               GO2 internal Ethernet switch
                        |
        +---------------+---------------+
        |                               |
   +---------+                    +-----------+
   | Jetson  |                    | GO2 MCU   |
   | .123.15 |                    | .123.161  |
   +---------+                    +-----------+
                                        |
                                  +-----------+
                                  | GO2 EDU   |
                                  | built-in  |
                                  | compute   |
                                  | .123.13   |
                                  +-----------+
```

**Key addresses on the GO2 internal network (192.168.123.0/24):**

| Device | Typical IP | Notes |
|--------|------------|-------|
| Laptop (your dev machine) | 192.168.123.100 | Static, set manually |
| Your Jetson Orin | 192.168.123.15 | Static, set manually (use .18 if .15 is taken) |
| GO2 main control board (MCU) | 192.168.123.161 | Fixed in firmware — do not change |
| GO2 EDU built-in compute board | 192.168.123.13 | Documented default (EDU only) — verify with `nmap` scan |
| GO2 LiDAR (if equipped) | varies | Scan with `nmap -sn 192.168.123.0/24` to discover |
| GO2 Wi-Fi AP (robot's own hotspot) | 192.168.12.1 | **Different subnet (12.x, not 123.x)** |

> The GO2's own Wi-Fi hotspot uses **192.168.12.x**, not **192.168.123.x**. These are completely separate networks. The wired internal network (192.168.123.x) is what this guide uses for all communication.

> If you have a GO2 EDU, the built-in compute board (documented at `.13`) is already present on the network. Your new Jetson joins as a second compute unit — choose an unused IP (e.g., `.15` or `.18`) and verify there is no conflict by running `nmap -sn 192.168.123.0/24` before assigning. Exact internal addresses may vary by firmware version, so always scan first.

---

## FAQ

**Q: Which JetPack version should I use?**
A: This guide targets **JetPack 6.x** (Ubuntu 22.04). This is the recommended path because ROS 2 Humble installs cleanly from apt on Ubuntu 22.04. JetPack 5.x also supports Orin modules (from version 5.0.2+), but it uses Ubuntu 20.04, where ROS 2 Humble binary packages are not available. Before flashing, verify that your carrier board has JetPack 6.x driver support — check the carrier board manufacturer's documentation.

**Q: Can I use the GO2's built-in Wi-Fi hotspot to connect my laptop AND give the Jetson internet?**
A: The GO2's hotspot (192.168.12.x) does not provide internet access -- it is only for the Unitree mobile app. For internet on the Jetson, share your laptop's Wi-Fi over the wired Ethernet link as described in [docs/05-internet-sharing.md](docs/05-internet-sharing.md).

**Q: Do I need a monitor and keyboard for the Jetson?**
A: Only for the very first boot if you did not pre-configure a headless image. After the initial setup, you can do everything over SSH. See [docs/03-first-boot.md](docs/03-first-boot.md) for headless options.

**Q: My Jetson cannot see the GO2 head unit at 192.168.123.161. What is wrong?**
A: First confirm your Jetson has a static IP in the 192.168.123.x/24 range. Then check that the Ethernet cable is plugged into the GO2's internal network switch (not the external debug port). See the troubleshooting table below and [docs/08-troubleshooting.md](docs/08-troubleshooting.md).

**Q: Which ROS 2 distribution should I install?**
A: **ROS 2 Humble Hawksbill (LTS)**, supported through May 2027. It installs cleanly from apt on Ubuntu 22.04 (which is what JetPack 6.x provides). See [docs/06-ros2-bootstrap.md](docs/06-ros2-bootstrap.md).

**Q: Will this guide work for the GO2 Air / GO2 Pro / GO2 EDU?**
A: The networking layout is the same across GO2 variants. However, the EDU version exposes more ROS 2 topics and services out of the box. The Air and Pro models may require Unitree's SDK for low-level control.

---

## Troubleshooting Quick Reference

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Cannot ping 192.168.123.161 from Jetson | Jetson IP not in 192.168.123.x/24 range, or wrong Ethernet port | Verify static IP with `ip addr show`. Ensure cable is on the internal network switch. |
| SSH connection refused | SSH server not running on Jetson | Run `sudo systemctl enable --now ssh` on the Jetson. |
| `apt update` fails on Jetson (no internet) | Internet sharing not configured on laptop | Follow [docs/05-internet-sharing.md](docs/05-internet-sharing.md). Check that IP forwarding is enabled on the laptop: `cat /proc/sys/net/ipv4/ip_forward` should return `1`. |
| Jetson gets a 169.254.x.x address | DHCP failed and no static IP is set | Set a manual static IP. See [docs/04-networking-and-ssh.md](docs/04-networking-and-ssh.md). |
| SDK Manager does not detect the Jetson | Jetson not in recovery mode, or bad USB cable | Hold the recovery button while powering on. Try a different USB-C cable. |
| ROS 2 topics from GO2 not visible | ROS 2 alone does not publish GO2 topics | You need the Unitree SDK or `unitree_ros2` package installed and configured. After that, check DDS discovery and `ROS_DOMAIN_ID`. See [docs/07-go2-notes.md](docs/07-go2-notes.md). |
| Jetson overheats and throttles | Insufficient cooling inside GO2 enclosure | Add a fan or heatsink. Check thermal status with `tegrastats`. |
| GO2 robot behaves erratically after changes | Internal network IPs were modified | Never change the GO2's factory-assigned IPs. Power cycle the robot to restore defaults. |

---

## Safety and Disclaimers

- **Always power off the GO2's motors before testing new software.** Use the Unitree app or the physical power switch to disable motor control while you are developing. An unexpected command can cause the robot to jump or fall.
- **Do not modify the GO2's internal IP addresses.** The GO2 main control board (192.168.123.161), EDU built-in compute board (typically 192.168.123.13), and other internal devices use factory-assigned IPs. Changing them can break the robot's internal communication and may require a factory reset.
- **Secure your Jetson.** If you expose SSH or other services, use key-based authentication and disable password login. The GO2's internal network is not firewalled.
- **Back up before flashing.** Re-flashing the Jetson erases all data on the target storage device.
- **Mind the power budget.** The Jetson Orin NX can draw up to 25W. Verify that your power supply and wiring inside the GO2 can handle the load, especially under GPU-intensive workloads.
- **This guide is community-maintained** and is not affiliated with or endorsed by Unitree Robotics or NVIDIA. Use at your own risk.

---

## Contributing

Contributions are welcome. If you find an error, have a better way to do something, or want to add support for a different Jetson or GO2 variant:

1. Fork this repository.
2. Create a branch for your change.
3. Submit a pull request with a clear description of what you changed and why.

Please keep the tone beginner-friendly and include exact commands where possible. Mark commands with `[Laptop]`, `[Jetson]`, or `[GO2]` to indicate where they should be run.

---

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
