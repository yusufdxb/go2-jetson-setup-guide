# 04 - Networking and SSH

## Overview

This guide covers how three devices talk to each other on the Unitree GO2's internal network:

| Device | Role | IP Address |
|--------|------|------------|
| **GO2 main board** | Robot controller | `192.168.123.161` (fixed) |
| **Jetson Orin NX/Nano** | Your compute board, mounted on the GO2 | `192.168.123.15` (we set this) |
| **Laptop** | Your development machine | `192.168.123.100` (we set this) |

All three devices sit on the same `192.168.123.x` subnet. This is the GO2's internal network -- the GO2 uses it for all its onboard communication.

> **Warning:** Do NOT change the GO2's IP addresses. They are hardcoded in Unitree's firmware. Changing them can break the robot's internal communication.

---

## Network Topology

There are two ways to physically connect everything.

### Option A: Through the GO2's Ethernet Port (Recommended)

```
Laptop  ----Ethernet---->  GO2 external Ethernet port  ---->  internal switch  ---->  Jetson
```

The GO2 has an external Ethernet port that connects to an internal network switch. The Jetson is also connected to this internal switch. When you plug your laptop into the GO2's Ethernet port, all three devices end up on the same `192.168.123.x` network automatically.

### Option B: Direct Connection to Jetson + Separate Path to GO2

```
Laptop  ----USB Ethernet adapter---->  Jetson (direct)
Laptop  ----Wi-Fi or another cable---->  GO2
```

This option uses a USB Ethernet adapter on your laptop to connect directly to the Jetson. You then connect to the GO2 separately (for example, over the GO2's Wi-Fi). This is more complex and generally not needed for most setups.

---

## Step 1: Set a Static IP on the Jetson

You need to give the Jetson a fixed IP address on the `192.168.123.x` subnet so you can always find it.

First, identify the Jetson's Ethernet interface name:

```bash
# [Jetson]
ip link show
```

Look for an interface like `eth0` or `enp1s0` -- it will be the one that is not `lo` (loopback). In the examples below we use `eth0`, but substitute your actual interface name.

Set the static IP using `nmcli`:

```bash
# [Jetson]
sudo nmcli con add type ethernet ifname eth0 con-name go2-network \
  ip4 192.168.123.15/24
```

Bring the connection up:

```bash
# [Jetson]
sudo nmcli con up go2-network
```

**Verify:**

```bash
# [Jetson]
ip addr show eth0
```

**Expected output** (look for the IP you set):

```
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> ...
    inet 192.168.123.15/24 ...
```

> **If this fails...** Make sure the Ethernet cable is plugged in and the interface is `UP`. Run `ip link set eth0 up` if needed, and double-check the interface name with `ip link show`.

---

## Step 2: Set a Static IP on Your Laptop

On your laptop, set the Ethernet interface that connects to the GO2/Jetson to `192.168.123.100`.

First, find the interface name:

```bash
# [Laptop]
ip link show
```

Look for the wired Ethernet interface (e.g., `eth0`, `enp3s0`, or the USB adapter name). Then set the IP:

```bash
# [Laptop]
sudo nmcli con add type ethernet ifname eth0 con-name go2-network \
  ip4 192.168.123.100/24
sudo nmcli con up go2-network
```

> Replace `eth0` with your actual interface name.

**Verify:**

```bash
# [Laptop]
ip addr show eth0
```

---

## Step 3: Verify Connectivity

Run these pings to confirm all devices can see each other.

**From your laptop:**

```bash
# [Laptop] Ping the Jetson
ping -c 3 192.168.123.15
```

**Expected output:**

```
PING 192.168.123.15 (192.168.123.15) 56(84) bytes of data.
64 bytes from 192.168.123.15: icmp_seq=1 ttl=64 time=0.5 ms
...
3 packets transmitted, 3 received, 0% packet loss
```

```bash
# [Laptop] Ping the GO2 main board
ping -c 3 192.168.123.161
```

**From the Jetson:**

```bash
# [Jetson] Ping the GO2 main board
ping -c 3 192.168.123.161
```

```bash
# [Jetson] Ping the laptop
ping -c 3 192.168.123.100
```

> **If pings fail...**
> - Check cables are connected and interface is UP: `ip link show`
> - Make sure all devices are on the `192.168.123.x/24` subnet
> - Check for conflicting network connections: `nmcli con show --active`
> - Make sure the GO2 is powered on (the internal switch only works when the robot is on)

---

## Step 4: SSH into the Jetson

Once the network is set up, you can SSH from your laptop to the Jetson:

```bash
# [Laptop]
ssh jetson-user@192.168.123.15
```

> Replace `jetson-user` with whatever username you created during the Jetson's OS setup (common defaults are `jetson`, `nvidia`, or a custom name you chose).

You will be prompted for the Jetson user's password.

---

## Step 5: Set Up SSH Keys (No More Passwords)

Typing a password every time is tedious. Set up SSH keys so you can log in automatically.

### Generate a key pair on your laptop (skip if you already have one)

```bash
# [Laptop]
ssh-keygen -t ed25519
```

Press Enter for all prompts to accept defaults (or set a passphrase if you prefer).

**Expected output:**

```
Generating public/private ed25519 key pair.
Enter file in which to save the key (/home/you/.ssh/id_ed25519):
...
Your public key has been saved in /home/you/.ssh/id_ed25519.pub
```

### Copy the public key to the Jetson

```bash
# [Laptop]
ssh-copy-id jetson-user@192.168.123.15
```

You will be asked for the Jetson password one last time. After this, future SSH connections will use the key instead.

**Verify:**

```bash
# [Laptop]
ssh jetson-user@192.168.123.15
```

You should get in without a password prompt.

> **If this fails...** Check that the `.ssh` directory on the Jetson has correct permissions: `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys` (run on the Jetson).

---

## Step 6: SSH Config for Convenience

Instead of typing the full `ssh jetson-user@192.168.123.15` command every time, add an entry to your laptop's SSH config.

Open (or create) the config file:

```bash
# [Laptop]
mkdir -p ~/.ssh
nano ~/.ssh/config
```

Add this block:

```
Host jetson
    HostName 192.168.123.15
    User jetson-user
```

> Replace `jetson-user` with your actual Jetson username.

Save and close the file. Now you can simply run:

```bash
# [Laptop]
ssh jetson
```

---

## Step 7: Firewall on the Jetson

The Jetson may have a firewall (`ufw`) enabled that blocks SSH connections.

**Option A: Allow SSH through the firewall**

```bash
# [Jetson]
sudo ufw allow ssh
sudo ufw reload
```

**Option B: Disable the firewall entirely (simpler for development)**

```bash
# [Jetson]
sudo ufw disable
```

**Check firewall status:**

```bash
# [Jetson]
sudo ufw status
```

> For a development setup on an isolated robot network, disabling the firewall is usually fine. For any deployment exposed to other networks, keep it enabled and only allow the ports you need.

---

## Useful Diagnostic Commands

These commands are handy when things are not working:

```bash
# Show all network interfaces and their IP addresses
ip addr show

# Show the routing table (where traffic goes)
ip route show

# Show status of all network connections managed by NetworkManager
nmcli device status

# Show active connections
nmcli con show --active

# Show which interface a specific IP is reachable through
ip route get 192.168.123.161
```

---

## Summary

At this point you should have:

- [x] Jetson at `192.168.123.15` on the GO2's internal network
- [x] Laptop at `192.168.123.100` on the same network
- [x] GO2 main board reachable at `192.168.123.161`
- [x] SSH access from laptop to Jetson without a password
- [x] SSH config entry so you can just type `ssh jetson`
- [x] Firewall configured to allow SSH

Next: [05 - Internet Sharing](05-internet-sharing.md) -- get the Jetson online for installing packages.
