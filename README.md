# Unitree GO2 + Jetson Orin Setup Guide

**Get your NVIDIA Jetson Orin NX / Orin Nano running on a Unitree GO2 quadruped robot -- from first boot to ROS 2.**

---

## Who This Is For

You have physically mounted a Jetson Orin NX or Jetson Orin Nano inside (or on top of) your Unitree GO2. The board is wired for power and connected to the GO2's internal Ethernet network. Now you are staring at it wondering: *what next?*

This guide walks you through flashing the Jetson, getting on the network, sharing internet from your laptop, installing ROS 2, and talking to the GO2 -- step by step, with exact commands.

No prior Jetson or ROS experience is assumed. If you can open a terminal and type commands, you can follow this guide.

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

1. **Flash JetPack 5.x** onto the Jetson using NVIDIA SDK Manager from your laptop.
2. **Boot the Jetson** and complete the OEM setup (user account, locale, etc.).
3. **Connect via Ethernet** -- plug the Jetson into the GO2's internal network switch.
4. **Assign a static IP** on the Jetson's Ethernet interface in the `192.168.123.x` range (e.g., `192.168.123.15`).

   ```bash
   # [Jetson] Set static IP via netplan or nmcli
   sudo nmcli con mod "Wired connection 1" \
     ipv4.addresses 192.168.123.15/24 \
     ipv4.gateway 192.168.123.1 \
     ipv4.method manual
   sudo nmcli con up "Wired connection 1"
   ```

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

8. **Install ROS 2 Humble** following the official instructions or the bootstrap script:

   ```bash
   # [Jetson]
   ./scripts/install-ros2.sh
   ```

9. **Verify connectivity to the GO2** head unit at `192.168.123.161`:

   ```bash
   # [Jetson]
   ping 192.168.123.161
   ```

10. **Test a ROS 2 topic** from the GO2's built-in ROS bridge (if available on your model):

    ```bash
    # [Jetson]
    source /opt/ros/humble/setup.bash
    ros2 topic list
    ```

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
| `scripts/set-static-ip.sh` | Jetson | Assigns a static IP in the 192.168.123.x range via nmcli |
| `scripts/share-internet.sh` | Laptop | Enables NAT and IP forwarding to share internet with the Jetson |
| `scripts/install-ros2.sh` | Jetson | Installs ROS 2 Humble and common dependencies |
| `scripts/setup-workspace.sh` | Jetson | Creates a colcon workspace and sources it in .bashrc |
| `scripts/test-go2-connection.sh` | Jetson | Pings known GO2 internal IPs and reports status |
| `scripts/undo-internet-sharing.sh` | Laptop | Removes the NAT/forwarding rules set by share-internet.sh |

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
                   | .123.10 |
                   +---------+
                        |
                    Ethernet
                   (192.168.123.x)
                        |
        +---------------+---------------+
        |                               |
   +---------+                    +-----------+
   | Jetson  |                    | GO2 Head  |
   | .123.15 |----Ethernet-----  | .123.161  |
   +---------+                    +-----------+
                                        |
                                  +-----------+
                                  | GO2 Body  |
                                  | .123.13   |
                                  +-----------+
```

**Key addresses on the GO2 internal network (192.168.123.0/24):**

| Device | Typical IP |
|--------|------------|
| Laptop (your dev machine) | 192.168.123.10 |
| Jetson Orin (your board) | 192.168.123.15 |
| GO2 head unit (Jetson Nano inside GO2) | 192.168.123.161 |
| GO2 body MCU / motion controller | 192.168.123.13 |
| GO2 LiDAR (if equipped) | 192.168.123.120 |
| GO2 Wi-Fi AP (robot's own hotspot) | 192.168.12.1 |

Note: The GO2's own Wi-Fi hotspot uses a **different** subnet (192.168.12.x). The wired internal network uses 192.168.123.x. Do not confuse the two.

---

## FAQ

**Q: Which JetPack version should I use?**
A: JetPack 5.1.2 or later is recommended for the Orin NX and Orin Nano. JetPack 6.x works as well but check that your specific carrier board has driver support. The guides in this repo assume JetPack 5.x unless noted otherwise.

**Q: Can I use the GO2's built-in Wi-Fi hotspot to connect my laptop AND give the Jetson internet?**
A: The GO2's hotspot (192.168.12.x) does not provide internet access -- it is only for the Unitree mobile app. For internet on the Jetson, share your laptop's Wi-Fi over the wired Ethernet link as described in [docs/05-internet-sharing.md](docs/05-internet-sharing.md).

**Q: Do I need a monitor and keyboard for the Jetson?**
A: Only for the very first boot if you did not pre-configure a headless image. After the initial setup, you can do everything over SSH. See [docs/03-first-boot.md](docs/03-first-boot.md) for headless options.

**Q: My Jetson cannot see the GO2 head unit at 192.168.123.161. What is wrong?**
A: First confirm your Jetson has a static IP in the 192.168.123.x/24 range. Then check that the Ethernet cable is plugged into the GO2's internal network switch (not the external debug port). See the troubleshooting table below and [docs/08-troubleshooting.md](docs/08-troubleshooting.md).

**Q: Which ROS 2 distribution should I install?**
A: ROS 2 Humble Hawksbill (LTS). It is the best-supported distribution on Ubuntu 22.04, which is the default OS for JetPack 5.x on Orin modules.

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
| ROS 2 topics from GO2 not visible | DDS discovery issue or firewall | Ensure both devices are on the same subnet. Try setting `export ROS_DOMAIN_ID=0`. Check no firewall is blocking UDP multicast. |
| Jetson overheats and throttles | Insufficient cooling inside GO2 enclosure | Add a fan or heatsink. Check thermal status with `tegrastats`. |
| GO2 robot behaves erratically after changes | Internal network IPs were modified | Never change the GO2's factory-assigned IPs. Power cycle the robot to restore defaults. |

---

## Safety and Disclaimers

- **Always power off the GO2's motors before testing new software.** Use the Unitree app or the physical power switch to disable motor control while you are developing. An unexpected command can cause the robot to jump or fall.
- **Do not modify the GO2's internal IP addresses.** The GO2 head unit (192.168.123.161), body controller (192.168.123.13), and other internal devices use hard-coded IPs. Changing them can break the robot's internal communication and may require a factory reset.
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
