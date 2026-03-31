# 03 -- First Boot and Initial Configuration

The Jetson has been flashed. This page covers the first boot, OS setup, networking for the GO2, and verifying that everything works.

---

## Step 1: Connect Peripherals

**[Jetson]** (physically, at your desk)

Connect the following to your Jetson carrier board:

- **Monitor** via HDMI or DisplayPort (depends on your carrier board)
- **USB keyboard**
- **USB mouse**
- **Power supply** (USB-C PD or barrel jack)

Power on the Jetson by pressing the power button (or simply connecting power, depending on your carrier board).

### Alternative: Serial Console (Headless)

If you do not have a monitor available, you can use a serial console:

**[Laptop]**

```bash
# Connect a USB serial debug cable from the Jetson carrier board's debug/UART port to your laptop.
# Find the serial device (the exact device node depends on your USB-serial adapter):
ls /dev/ttyUSB* /dev/ttyACM*
```

```bash
# Connect at 115200 baud:
sudo apt install -y screen
sudo screen /dev/ttyUSB0 115200
```

> The NVIDIA Orin DevKit carrier board exposes a USB debug port. When connected, it typically appears as `/dev/ttyACM0` on the host. Third-party carrier boards vary — check your board's documentation for the UART debug port location.

---

## Step 2: Ubuntu First-Boot Setup (OOBE)

**[Jetson]**

Ubuntu will walk you through initial setup. Choose the following:

| Setting | Recommended Value |
|---------|-------------------|
| **Language** | English |
| **Keyboard layout** | Your preference |
| **Timezone** | Your local timezone |
| **Username** | `jetson` (or your preference) |
| **Computer name (hostname)** | `jetson-go2` |
| **Password** | Something you will remember -- you will SSH with this constantly |

Complete the setup and wait for the Ubuntu desktop to appear.

---

## Step 3: Enable SSH

**[Jetson]**

Open a terminal on the Jetson (Ctrl+Alt+T) and run:

```bash
sudo apt update && sudo apt install -y openssh-server
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Verification:**

```bash
sudo systemctl status ssh
```

**Expected output:**

```
● ssh.service - OpenBSD Secure Shell server
     Loaded: loaded (/lib/systemd/system/ssh.service; enabled; ...)
     Active: active (running) since ...
```

The key things to check: `enabled` (will start on boot) and `active (running)`.

**If this fails...**
- If `apt update` fails, check your internet connection. Connect the Jetson to your router via Ethernet or join Wi-Fi.
- If SSH is already installed (JetPack sometimes includes it), you just need to make sure it is enabled and running.

---

## Step 4: Set a Static IP for the GO2 Network

**[Jetson]**

The GO2's internal network uses the subnet `192.168.123.0/24`. You need to assign your Jetson a static IP on this subnet so it can communicate with the GO2's MCU and other internal devices.

> **Note**: Do this on the Ethernet port you plan to connect to the GO2's internal network. If your carrier board has two Ethernet ports, pick one and note which one it is.

### Find your Ethernet interface name

```bash
ip link show
```

**Expected output** (look for an Ethernet interface -- typically `eth0` or `enp1s0`):

```
1: lo: <LOOPBACK,UP,LOWER_UP> ...
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
3: wlan0: <BROADCAST,MULTICAST> ...
```

Note the name (e.g., `eth0`). If you see something like `enp1s0` or `end0`, use that instead.

### Create a netplan configuration

```bash
sudo nano /etc/netplan/01-go2-network.yaml
```

Paste the following (replace `eth0` with your actual interface name if different):

```yaml
network:
  version: 2
  renderer: NetworkManager
  ethernets:
    eth0:
      dhcp4: no
      addresses:
        - 192.168.123.15/24
```

> **Important**: If your GO2 EDU already has an internal Jetson using `192.168.123.15`, choose a different IP like `192.168.123.18`. Refer to the network table in [01 -- Hardware Overview](01-hardware-overview.md). Scan the network first: `nmap -sn 192.168.123.0/24`.

Save the file (Ctrl+O, Enter, Ctrl+X in nano).

### Apply the configuration

```bash
sudo netplan apply
```

**Verification:**

```bash
ip addr show eth0
```

**Expected output** (look for your static IP):

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 192.168.123.15/24 brd 192.168.123.255 scope global eth0
```

**If this fails...**
- If `netplan apply` shows YAML errors, check your indentation. YAML is sensitive to spaces (use spaces, not tabs). Each indent level is 2 spaces.
- If the IP does not appear, make sure the Ethernet cable is connected and the interface is up: `sudo ip link set eth0 up`.
- If you are using NetworkManager and netplan conflicts, you may need to configure the static IP through `nmcli` instead:
  ```bash
  sudo nmcli con add type ethernet con-name go2-net ifname eth0 ip4 192.168.123.15/24
  sudo nmcli con up go2-net
  ```

---

## Step 5: System Updates

**[Jetson]**

```bash
sudo apt update && sudo apt full-upgrade -y
```

This can take several minutes. It updates all packages including any JetPack components.

**If this fails...**
- Make sure the Jetson has internet access. If it only has the static GO2 Ethernet configured, connect via Wi-Fi or a second Ethernet port for internet.
- If you see GPG key errors for NVIDIA repos, fetch the key using the modern keyring approach:
  ```bash
  sudo curl -fsSL https://repo.download.nvidia.com/jetson/jetson-ota-public.asc \
    -o /usr/share/keyrings/nvidia-jetson-ota.gpg
  ```
  Then update your NVIDIA apt source entries to reference `signed-by=/usr/share/keyrings/nvidia-jetson-ota.gpg`. Check `/etc/apt/sources.list.d/` for the NVIDIA repo files.

---

## Step 6: Install Basic Packages

**[Jetson]**

```bash
sudo apt install -y build-essential cmake git curl wget htop net-tools nano
```

These are commonly needed tools for development and debugging.

---

## Step 7: Install and Run jtop (Jetson Health Monitor)

**[Jetson]**

`jtop` is a terminal-based monitoring tool built specifically for Jetson boards. It shows GPU usage, CPU temps, RAM, power draw, and installed JetPack components.

```bash
sudo pip3 install jetson-stats
```

After installing, you need to **reboot** (or at minimum restart the `jtop` service):

```bash
sudo systemctl restart jtop.service
```

Then run:

```bash
sudo jtop
```

**Expected output:**

A full-screen terminal dashboard showing:

- **GPU**: usage percentage and frequency
- **CPU**: per-core usage and temperature
- **RAM**: used / total
- **Power**: current wattage
- **JetPack info**: CUDA version, cuDNN version, TensorRT version, L4T version

Press `q` to quit jtop.

**If this fails...**
- If `pip3` is not found: `sudo apt install -y python3-pip`
- If `jtop` shows "No NVIDIA Jetson found," you may be running in a VM or the NVIDIA drivers are not loaded. Check `dmesg | grep -i nvidia` for errors.

---

## Step 8: Verify CUDA

**[Jetson]**

CUDA should already be installed as part of JetPack. Verify:

```bash
nvcc --version
```

**Expected output:**

```
nvcc: NVIDIA (R) Cuda compiler driver
Copyright (c) 2005-2024 NVIDIA Corporation
Built on ...
Cuda compilation tools, release 12.x, Vxx.x.x
```

The important thing is that `nvcc` runs and shows a CUDA 12.x version.

**If this fails...**
- If `nvcc` is not found, CUDA may not be in your PATH. Add it:
  ```bash
  echo 'export PATH=/usr/local/cuda/bin:$PATH' >> ~/.bashrc
  echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> ~/.bashrc
  source ~/.bashrc
  nvcc --version
  ```
- If CUDA is genuinely not installed (e.g., you skipped SDK components during flash), install it:
  ```bash
  sudo apt install -y nvidia-jetpack
  ```
  This is a meta-package that pulls in CUDA, cuDNN, TensorRT, and other JetPack components. It will download several GB.

---

## Step 9: Reboot and Verify Persistence

**[Jetson]**

```bash
sudo reboot
```

After the Jetson comes back up, verify that your configuration survived the reboot:

```bash
# Check static IP is still set
ip addr show eth0

# Check SSH is running
sudo systemctl status ssh

# Check CUDA is still in PATH
nvcc --version
```

All three should return the same results as before.

---

## Step 10: Run the First Boot Check Script

**[Jetson]**

If this repository includes a check script, run it to verify everything at once:

```bash
# Clone the guide repo (or copy the script to the Jetson)
git clone https://github.com/yusufdxb/go2-jetson-setup-guide.git ~/go2-jetson-setup-guide
cd ~/go2-jetson-setup-guide
chmod +x scripts/jetson_first_boot_check.sh
./scripts/jetson_first_boot_check.sh
```

The script checks: OS version, CUDA, GPU, disk space, RAM, SSH server, internet connectivity, and jtop. It prints a PASS/FAIL/WARN summary. Fix any FAIL items before mounting the Jetson on the GO2.

---

## Quick SSH Test from Your Laptop

Once the Jetson is configured and connected to the same network as your laptop (either directly or through the GO2):

**[Laptop]**

```bash
ssh jetson@192.168.123.15
```

**Expected output:**

```
jetson@jetson-go2:~$
```

If this works, you are ready to mount the Jetson on the GO2 and start developing.

**If this fails...**
- Make sure your laptop is on the `192.168.123.x` subnet (e.g., connected to the GO2's Ethernet or configured with a static IP in the same range).
- Verify the Jetson's IP: on the Jetson, run `ip addr show eth0`.
- Check that SSH is running on the Jetson: `sudo systemctl status ssh`.
- Check for firewall rules: `sudo ufw status` -- if active, allow SSH with `sudo ufw allow ssh`.

---

## Summary

At this point your Jetson should have:

- [x] Ubuntu 22.04 (from JetPack 6.x) running
- [x] SSH enabled and running on boot
- [x] Static IP `192.168.123.15` (or your chosen address) on the GO2 Ethernet interface
- [x] System fully updated
- [x] Basic development tools installed
- [x] CUDA installed and working
- [x] `jtop` installed for monitoring

You are ready to mount the Jetson on the GO2 and begin building your application.
