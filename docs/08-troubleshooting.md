# 08 -- Troubleshooting

This page covers the most common problems you will run into when setting up a Jetson on the GO2. Each section follows the same structure: what you see (symptom), how to figure out what is wrong (diagnosis), and how to fix it.

If you do not know what is wrong, skip to [Section 10: General Diagnostic Checklist](#10-general-diagnostic-checklist) at the bottom and work through it step by step.

---

## 1. Jetson Not Reachable (Can't Ping or SSH)

### Symptom

You run `ping 192.168.123.15` from your laptop and get `Destination Host Unreachable` or 100% packet loss.

### Diagnosis

**Check the physical cable:**

Is the Ethernet cable plugged in on both ends? Is the link light on the Jetson's Ethernet port lit?

**Check that the interface is UP:**

```bash
# [Jetson]
ip link show
```

Look for your Ethernet interface (e.g., `eth0` or `enp1s0`). The output should say `UP` and `LOWER_UP`. If it says `DOWN`, the cable is not detected or the interface is disabled.

**Check the IP address:**

```bash
# [Jetson]
ip addr show eth0
```

Look for a line like `inet 192.168.123.15/24`. If there is no `inet` line, the IP is not set.

**Check from the laptop side too:**

```bash
# [Laptop]
ip addr show
```

Make sure your laptop's Ethernet interface has an IP on the `192.168.123.x/24` subnet (e.g., `192.168.123.100`).

### Fix

**If the interface is DOWN:**

```bash
# [Jetson]
sudo ip link set eth0 up
```

**If the IP is not set:**

```bash
# [Jetson]
sudo nmcli con add type ethernet ifname eth0 con-name go2-network \
  ip4 192.168.123.15/24
sudo nmcli con up go2-network
```

**If the IP is set but on the wrong subnet** (e.g., `10.x.x.x` or `192.168.1.x`):

Delete the incorrect connection and create the correct one:

```bash
# [Jetson]
nmcli con show
# Find the name of the wrong connection, then:
sudo nmcli con delete "connection-name-here"
sudo nmcli con add type ethernet ifname eth0 con-name go2-network \
  ip4 192.168.123.15/24
sudo nmcli con up go2-network
```

**If a Netplan config is interfering:**

Some Jetson setups have Netplan files in `/etc/netplan/` that can override NetworkManager settings. If your `nmcli` changes are not taking effect, check for conflicting configs:

```bash
# [Jetson]
ls /etc/netplan/
cat /etc/netplan/*.yaml
```

If a Netplan file sets a conflicting IP or enables DHCP on the same interface, either remove it (`sudo rm /etc/netplan/01-*.yaml && sudo netplan apply`) or edit it to use `renderer: NetworkManager` so NetworkManager remains in control.

### Verify

```bash
# [Laptop]
ping -c 3 192.168.123.15
```

You should see `3 packets transmitted, 3 received, 0% packet loss`.

---

## 2. SSH Connection Refused or Timeout

### Symptom

You can ping the Jetson, but `ssh jetson-user@192.168.123.15` gives `Connection refused` or hangs until it times out.

### Diagnosis

**Check if the SSH server is installed and running:**

```bash
# [Jetson]
sudo systemctl status ssh
```

If it says `not found`, the SSH server is not installed. If it says `inactive` or `dead`, the service is stopped.

**Check if a firewall is blocking port 22:**

```bash
# [Jetson]
sudo ufw status
```

If it says `active` and there is no rule allowing SSH, connections will be blocked.

**Check if you are using the correct IP:**

```bash
# [Laptop]
ping -c 1 192.168.123.15
```

If the ping succeeds but SSH does not, the problem is on the Jetson (SSH service or firewall). If the ping also fails, see [Section 1](#1-jetson-not-reachable-cant-ping-or-ssh).

### Fix

**Install the SSH server (if missing):**

```bash
# [Jetson]
sudo apt update
sudo apt install -y openssh-server
```

**Start and enable the SSH server:**

```bash
# [Jetson]
sudo systemctl enable ssh
sudo systemctl start ssh
```

**Allow SSH through the firewall:**

```bash
# [Jetson]
sudo ufw allow ssh
sudo ufw reload
```

Or disable the firewall entirely for development:

```bash
# [Jetson]
sudo ufw disable
```

### Verify

```bash
# [Laptop]
ssh jetson-user@192.168.123.15
```

You should get a login prompt or log in directly if SSH keys are set up.

---

## 3. No Internet on Jetson

### Symptom

The Jetson can ping devices on the `192.168.123.x` network, but cannot reach the internet. `ping 8.8.8.8` fails. `apt update` fails.

### Diagnosis

Work through these checks in order. Each one tests one layer of the connection.

**Step 1: Can you reach the gateway (your laptop)?**

```bash
# [Jetson]
ping -c 3 192.168.123.100
```

If this fails, the local network is broken -- go back to [Section 1](#1-jetson-not-reachable-cant-ping-or-ssh).

**Step 2: Is the default gateway set?**

```bash
# [Jetson]
ip route show
```

Look for a line like `default via 192.168.123.100`. If there is no default route, the Jetson does not know how to reach anything outside `192.168.123.x`.

**Step 3: Can you reach an external IP?**

```bash
# [Jetson]
ping -c 3 8.8.8.8
```

If this fails but the gateway ping worked, the problem is on the laptop side (NAT or IP forwarding).

**Step 4: Can you resolve DNS names?**

```bash
# [Jetson]
ping -c 3 google.com
```

If `ping 8.8.8.8` works but `ping google.com` fails with `Temporary failure in name resolution`, DNS is not configured.

### Fix

**Add the default gateway (if missing):**

```bash
# [Jetson]
sudo nmcli con mod go2-network ipv4.gateway 192.168.123.100
sudo nmcli con up go2-network
```

This stores the gateway in the `go2-network` connection profile so it persists across reboots.

**Enable IP forwarding on the laptop:**

```bash
# [Laptop]
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
```

To make it survive reboots:

```bash
# [Laptop]
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

**Set up NAT on the laptop:**

Replace `wlan0` with whatever interface your laptop uses for its internet connection (check with `ip route show` -- look at the `default via` line).

```bash
# [Laptop]
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

> Replace `eth0` with the interface connected to the GO2/Jetson network, and `wlan0` with your internet-facing interface.

**Fix DNS (if `ping 8.8.8.8` works but `ping google.com` does not):**

The persistent fix is to configure DNS through NetworkManager:

```bash
# [Jetson]
sudo nmcli con mod go2-network ipv4.dns "8.8.8.8 8.8.4.4"
sudo nmcli con up go2-network
```

To verify the setting took effect:

```bash
# [Jetson]
resolvectl status
```

Look for the DNS server listed under your Ethernet interface. If DNS is still failing, restart the resolver:

```bash
# [Jetson]
sudo systemctl restart systemd-resolved
```

### Verify

Run these three checks in order:

```bash
# [Jetson]
ping -c 3 192.168.123.100   # gateway reachable?
ping -c 3 8.8.8.8            # internet reachable?
ping -c 3 google.com         # DNS working?
```

All three should succeed with 0% packet loss.

---

## 4. apt Fails / Can't Download Packages

### Symptom

Running `sudo apt update` or `sudo apt install` gives errors like `Could not resolve`, `Failed to fetch`, or `Connection timed out`.

### Diagnosis

**Check internet connectivity first:**

```bash
# [Jetson]
ping -c 3 8.8.8.8
```

If this fails, the problem is not apt -- you have no internet. See [Section 3](#3-no-internet-on-jetson).

**Check DNS resolution:**

```bash
# [Jetson]
ping -c 3 ports.ubuntu.com
```

If `ping 8.8.8.8` works but `ping ports.ubuntu.com` fails, DNS is broken. See the DNS fix in [Section 3](#3-no-internet-on-jetson).

**Check the apt sources list:**

```bash
# [Jetson]
cat /etc/apt/sources.list
ls /etc/apt/sources.list.d/
```

After flashing JetPack, the sources sometimes point to NVIDIA repositories that require specific URLs. Make sure the base Ubuntu repositories are present and correctly formatted.

**Check if a proxy is needed:**

Some university and corporate networks require a proxy. If you are on such a network, ask your network administrator for the proxy address.

### Fix

**If DNS is the problem**, fix it using the steps in [Section 3](#3-no-internet-on-jetson).

**If apt sources are broken after a JetPack flash:**

```bash
# [Jetson]
sudo nano /etc/apt/sources.list
```

Make sure the file contains standard Ubuntu 22.04 repositories. A minimal working sources list for Jammy (Ubuntu 22.04 for ARM64):

```
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
```

> The Jetson uses ARM64, so it uses `ports.ubuntu.com/ubuntu-ports`, not the regular `archive.ubuntu.com`.

**If you need a proxy:**

```bash
# [Jetson]
sudo nano /etc/apt/apt.conf.d/proxy.conf
```

Add:

```
Acquire::http::Proxy "http://your-proxy-address:port";
Acquire::https::Proxy "http://your-proxy-address:port";
```

### Verify

```bash
# [Jetson]
sudo apt update
```

It should complete without errors and show a list of packages that can be upgraded.

---

## 5. Wrong Subnet / Duplicate IP / Bad Routes

### Symptom

Network behavior is unpredictable. Sometimes pings work, sometimes they do not. Or a device is unreachable even though it was working before.

### Diagnosis

**Check for duplicate IPs:**

If two devices share the same IP address, packets will randomly go to one or the other. This commonly happens when a device on the GO2's internal network already uses the address you assigned to your new Jetson (e.g., the EDU built-in compute board at `.13`, or another device you did not expect).

Scan the network to see what is already there:

```bash
# [Laptop]
nmap -sn 192.168.123.0/24
```

Or use `arping` to check a specific IP:

```bash
# [Laptop]
sudo arping -c 3 -I eth0 192.168.123.15
```

If you get replies from two different MAC addresses, there is a duplicate IP.

**Check that all devices are on `192.168.123.x/24`:**

```bash
# [Jetson]
ip addr show eth0
```

```bash
# [Laptop]
ip addr show eth0
```

Both should show IPs in the `192.168.123.x/24` range. If a device is on a different subnet (e.g., `192.168.1.x/24`), it cannot communicate with devices on `192.168.123.x/24` without a router.

**Check the routing table for conflicts:**

```bash
# [Jetson]
ip route show
```

Look for multiple routes to `192.168.123.0/24` through different interfaces, or routes that point to the wrong gateway. Conflicting routes cause unpredictable behavior.

### Fix

**If you have a duplicate IP**, change one of them. For your new Jetson:

```bash
# [Jetson]
sudo nmcli con modify go2-network ipv4.addresses 192.168.123.18/24
sudo nmcli con up go2-network
```

> Pick any unused address on `192.168.123.x` that is not already taken by the GO2 main board (`.161`), the EDU built-in compute board (typically `.13`), or your laptop (`.100`). Always scan the network first with `nmap -sn 192.168.123.0/24` to see what is in use — do not assume addresses are free.

**If the subnet mask is wrong** (e.g., `/32` instead of `/24`):

```bash
# [Jetson]
sudo nmcli con modify go2-network ipv4.addresses 192.168.123.15/24
sudo nmcli con up go2-network
```

**If there are conflicting routes**, remove the bad ones:

```bash
# [Jetson]
sudo ip route del 192.168.123.0/24 dev wrong-interface-name
```

### Verify

```bash
# [Jetson]
ip addr show eth0
ip route show
ping -c 3 192.168.123.161
ping -c 3 192.168.123.100
```

All pings should succeed, and the routing table should show a single clean route to `192.168.123.0/24`.

---

## 6. Robot (GO2) and Jetson Can't Communicate

### Symptom

The Jetson cannot ping the GO2 main board at `192.168.123.161`. Or the Jetson can reach your laptop but not the robot.

### Diagnosis

**Check the cable:**

The Jetson must be connected to the GO2's internal Ethernet network. If you plugged the Jetson into a port that is not on the internal switch, it will not be able to reach the GO2.

**Check that the GO2 is powered on:**

The internal Ethernet switch only works when the robot is powered on. If the GO2 is off, nothing inside it is reachable.

**Check that the Jetson is on the right subnet:**

```bash
# [Jetson]
ip addr show eth0
```

The Jetson must be on `192.168.123.x/24`.

**Check the Jetson's firewall:**

```bash
# [Jetson]
sudo ufw status
```

If the firewall is active, it might be blocking outgoing traffic or ICMP.

**Check the route to the GO2:**

```bash
# [Jetson]
ip route get 192.168.123.161
```

This should show that traffic goes through the Ethernet interface on the `192.168.123.x` network.

### Fix

**If the cable is wrong**, reconnect it to the correct port on the GO2's internal switch. See [01 -- Hardware Overview](01-hardware-overview.md) for the network diagram.

**If the firewall is blocking traffic:**

```bash
# [Jetson]
sudo ufw disable
```

**If the Jetson is on the wrong subnet**, fix the IP as shown in [Section 1](#1-jetson-not-reachable-cant-ping-or-ssh).

### Verify

```bash
# [Jetson]
ping -c 3 192.168.123.161
```

You should get replies from the GO2 main board.

---

## 7. Laptop Internet Sharing Stopped Working

### Symptom

The Jetson had internet access, but after rebooting the laptop (or sometimes the Jetson), internet no longer works. Local pings on `192.168.123.x` still work fine.

### Diagnosis

**Check IP forwarding on the laptop:**

```bash
# [Laptop]
cat /proc/sys/net/ipv4/ip_forward
```

If this returns `0`, IP forwarding is off. It resets to `0` on every reboot unless you made it persistent.

**Check iptables NAT rules on the laptop:**

```bash
# [Laptop]
sudo iptables -t nat -L POSTROUTING -n -v
```

If you do not see a `MASQUERADE` rule for your internet-facing interface (e.g., `wlan0`), the NAT rules were lost. Iptables rules do not survive reboots by default.

**Check the interface names:**

Interface names can change between reboots (e.g., a USB Ethernet adapter might be `enx...` one time and `eth1` another). Check that the interface names in your iptables rules match the current names:

```bash
# [Laptop]
ip link show
```

### Fix

**Re-enable IP forwarding:**

```bash
# [Laptop]
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward
```

**Re-apply iptables rules:**

```bash
# [Laptop]
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

> Replace `wlan0` and `eth0` with your actual interface names.

**Make it persistent so it survives reboots:**

Install `iptables-persistent`:

```bash
# [Laptop]
sudo apt install -y iptables-persistent
```

It will ask if you want to save current rules -- answer yes. If you already have it installed, save manually:

```bash
# [Laptop]
sudo netfilter-persistent save
```

And make IP forwarding persistent:

```bash
# [Laptop]
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ip-forward.conf
sudo sysctl -p /etc/sysctl.d/99-ip-forward.conf
```

### Verify

From the Jetson:

```bash
# [Jetson]
ping -c 3 8.8.8.8
ping -c 3 google.com
```

Both should succeed.

---

## 8. ROS 2 Topics Not Visible Between Machines

### Symptom

You run `ros2 topic list` on the Jetson and see topics published by the Jetson itself, but nothing from your laptop (or vice versa). Or `ros2 topic echo` shows no data for topics you know are being published on another machine.

### Diagnosis

**Check that both machines use the same ROS_DOMAIN_ID:**

```bash
# [Jetson]
echo $ROS_DOMAIN_ID
```

```bash
# [Laptop]
echo $ROS_DOMAIN_ID
```

If these are different (or one is unset while the other is set to a number), the machines are on different DDS domains and cannot see each other. The default value when unset is `0`.

**Check if multicast works on this network:**

ROS 2's default DDS discovery uses multicast. Multicast does not work on all network configurations -- particularly through some switches and routers.

On one machine, run the receiver:

```bash
# [Jetson]
ros2 multicast receive
```

On the other machine, send a test message:

```bash
# [Laptop]
ros2 multicast send
```

If the receiver does not print any message, multicast is not working between these machines.

**Check if a firewall is blocking DDS ports:**

DDS uses a range of UDP ports (typically 7400-7500+ depending on domain ID and number of participants).

```bash
# [Jetson]
sudo ufw status
```

```bash
# [Laptop]
sudo ufw status
```

### Fix

**Set the same ROS_DOMAIN_ID on all machines:**

```bash
# [Jetson]
export ROS_DOMAIN_ID=0
```

```bash
# [Laptop]
export ROS_DOMAIN_ID=0
```

To make it permanent, add `export ROS_DOMAIN_ID=0` to your `~/.bashrc` on both machines.

**If the firewall is blocking DDS, allow the ports:**

```bash
# [Jetson]
sudo ufw allow 7400:7500/udp
sudo ufw reload
```

Do the same on the laptop if its firewall is active.

**If multicast is not working, switch to Cyclone DDS with unicast discovery:**

This is the most reliable approach for the GO2's internal network.

Install Cyclone DDS (on both machines):

```bash
# [Jetson]
sudo apt install -y ros-${ROS_DISTRO}-rmw-cyclonedds-cpp
```

```bash
# [Laptop]
sudo apt install -y ros-${ROS_DISTRO}-rmw-cyclonedds-cpp
```

Create a Cyclone DDS config file on the Jetson:

```bash
# [Jetson]
mkdir -p ~/cyclone_dds
cat > ~/cyclone_dds/cyclone_dds.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<CycloneDDS xmlns="https://cdds.io/config" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain>
    <General>
      <Interfaces>
        <NetworkInterface name="eth0" />
      </Interfaces>
      <AllowMulticast>false</AllowMulticast>
      <EnableMulticastLoopback>false</EnableMulticastLoopback>
    </General>
    <Discovery>
      <Peers>
        <Peer address="192.168.123.100" />
        <!-- Only add 192.168.123.161 if a ROS 2 / DDS node is confirmed running on the GO2.
             The GO2 main board uses Unitree's own UDP protocol by default, not DDS. -->
      </Peers>
      <ParticipantIndex>auto</ParticipantIndex>
    </Discovery>
  </Domain>
</CycloneDDS>
XMLEOF
```

> Edit the `<Peer>` addresses to include all machines running ROS 2 nodes. Replace `eth0` with your actual interface name. Do **not** add the GO2 main board (`.161`) unless you have confirmed it is running a DDS-based ROS 2 stack.

Create a similar file on the laptop, but list the Jetson's IP as a peer:

```bash
# [Laptop]
mkdir -p ~/cyclone_dds
cat > ~/cyclone_dds/cyclone_dds.xml << 'XMLEOF'
<?xml version="1.0" encoding="UTF-8"?>
<CycloneDDS xmlns="https://cdds.io/config" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="https://cdds.io/config https://raw.githubusercontent.com/eclipse-cyclonedds/cyclonedds/master/etc/cyclonedds.xsd">
  <Domain>
    <General>
      <Interfaces>
        <NetworkInterface name="eth0" />
      </Interfaces>
      <AllowMulticast>false</AllowMulticast>
      <EnableMulticastLoopback>false</EnableMulticastLoopback>
    </General>
    <Discovery>
      <Peers>
        <Peer address="192.168.123.15" />
      </Peers>
      <ParticipantIndex>auto</ParticipantIndex>
    </Discovery>
  </Domain>
</CycloneDDS>
XMLEOF
```

Set the environment variables on both machines:

```bash
# [Jetson]
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///home/jetson-user/cyclone_dds/cyclone_dds.xml
```

```bash
# [Laptop]
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI=file:///home/your-user/cyclone_dds/cyclone_dds.xml
```

> Replace the paths with the actual path to the config file. Add these `export` lines to your `~/.bashrc` to make them permanent.

### Verify

On one machine:

```bash
# [Jetson]
ros2 topic pub /test std_msgs/msg/String "data: hello" --once
```

On the other:

```bash
# [Laptop]
ros2 topic echo /test std_msgs/msg/String
```

You should see the message appear.

---

## 9. Jetson Overheating or Throttling

### Symptom

The Jetson slows down under load. Programs take longer than expected. You might see `thermal throttling` messages in `dmesg` output.

### Diagnosis

**Install and run jtop:**

`jtop` is the best tool for monitoring Jetson thermals, power, and performance. If you do not have it installed:

```bash
# [Jetson]
sudo pip3 install -U jetson-stats
sudo systemctl restart jtop.service
```

Then run it:

```bash
# [Jetson]
sudo jtop
```

Look at:
- **Temperature**: CPU and GPU temps above 85C indicate thermal throttling.
- **Fan**: Is the fan spinning? Fan speed should increase under load.
- **Power mode**: Shows the current NVP model.

**Check the current power mode:**

```bash
# [Jetson]
sudo nvpmodel -q
```

This shows which power mode the Jetson is running in. Lower-power modes cap the CPU/GPU frequencies and number of active cores.

**Check for thermal throttling in the kernel log:**

```bash
# [Jetson]
dmesg | grep -i thermal
```

### Fix

**Make sure the fan is working:**

If the fan is not spinning, check its connector on the carrier board. You can also set the fan to maximum speed:

```bash
# [Jetson]
sudo jetson_clocks --fan
```

> `jetson_clocks` also sets CPU/GPU to maximum frequencies. It is good for testing but may increase power consumption.

**Switch to a higher-performance power mode (if needed):**

List available modes:

```bash
# [Jetson]
sudo nvpmodel -p
```

Set the desired mode (for example, mode 0 is usually the highest-performance mode):

```bash
# [Jetson]
sudo nvpmodel -m 0
```

**Improve airflow:**

If the Jetson is mounted inside the GO2 with no airflow, it will overheat. Make sure the heatsink and fan are not obstructed. Consider adding ventilation holes to any enclosure, or running the Jetson in a lower power mode.

### Verify

Run `sudo jtop` again under load and check that:
- The fan is spinning
- Temperatures stay below 80C
- No throttling indicators are shown

---

## 10. General Diagnostic Checklist

When something is not working and you do not know why, work through this list from top to bottom. Each step builds on the previous one. Do not skip ahead -- if a step fails, fix it before moving on.

### Layer 1: Physical

- [ ] Is the Ethernet cable plugged in on both ends?
- [ ] Are the link lights on? (small LEDs on the Ethernet port)
- [ ] Is the GO2 powered on? (the internal switch only works when the robot is running)
- [ ] Is the Jetson powered on?

```bash
# [Jetson]
ip link show
```

Every Ethernet interface should say `UP` and `LOWER_UP`. If an interface says `DOWN`, the cable is not connected or is faulty.

### Layer 2: IP Addresses

- [ ] Does every device have the correct IP?
- [ ] Are all devices on the `192.168.123.x/24` subnet?
- [ ] Are there any duplicate IPs?

```bash
# [Jetson]
ip addr show
```

```bash
# [Laptop]
ip addr show
```

| Device | Expected IP |
|--------|-------------|
| GO2 main board | `192.168.123.161` |
| Jetson | `192.168.123.15` (or your chosen address) |
| Laptop | `192.168.123.100` |

### Layer 3: Local Connectivity (Ping Test)

- [ ] Can the Jetson ping the laptop?
- [ ] Can the Jetson ping the GO2?
- [ ] Can the laptop ping the Jetson?
- [ ] Can the laptop ping the GO2?

```bash
# [Jetson]
ping -c 3 192.168.123.100
ping -c 3 192.168.123.161
```

```bash
# [Laptop]
ping -c 3 192.168.123.15
ping -c 3 192.168.123.161
```

If any ping fails, fix the issue (see [Section 1](#1-jetson-not-reachable-cant-ping-or-ssh) and [Section 6](#6-robot-go2-and-jetson-cant-communicate)) before continuing.

### Layer 4: Routing and Internet

- [ ] Does the Jetson have a default gateway set?
- [ ] Is IP forwarding enabled on the laptop?
- [ ] Are NAT rules in place on the laptop?

```bash
# [Jetson]
ip route show
```

Look for: `default via 192.168.123.100`

```bash
# [Laptop]
cat /proc/sys/net/ipv4/ip_forward
```

Should output `1`.

```bash
# [Laptop]
sudo iptables -t nat -L POSTROUTING -n
```

Should show a `MASQUERADE` rule.

### Layer 5: DNS

- [ ] Can the Jetson resolve domain names?

```bash
# [Jetson]
ping -c 3 8.8.8.8       # Tests raw internet connectivity
ping -c 3 google.com    # Tests DNS resolution
```

If the first works but the second fails, DNS is broken. See [Section 3](#3-no-internet-on-jetson).

### Layer 6: Services and Applications

- [ ] Is SSH running on the Jetson?
- [ ] Can you install packages with apt?
- [ ] Is ROS 2 sourced on both machines?
- [ ] Are ROS 2 topics visible?

```bash
# [Jetson]
sudo systemctl status ssh
sudo apt update
source /opt/ros/${ROS_DISTRO}/setup.bash
ros2 topic list
```

---

## Quick Reference: Common Commands

| What | Command | Run on |
|------|---------|--------|
| Show all IPs | `ip addr show` | Any |
| Show routing table | `ip route show` | Any |
| Show active connections | `nmcli con show --active` | Any |
| Check IP forwarding | `cat /proc/sys/net/ipv4/ip_forward` | Laptop |
| Check NAT rules | `sudo iptables -t nat -L -n -v` | Laptop |
| Check firewall | `sudo ufw status` | Any |
| Check SSH service | `sudo systemctl status ssh` | Jetson |
| Check DNS config | `resolvectl status` | Jetson |
| Scan network for devices | `nmap -sn 192.168.123.0/24` | Any |
| Monitor Jetson thermals | `sudo jtop` | Jetson |
| Check power mode | `sudo nvpmodel -q` | Jetson |
| Check ROS 2 DDS comms | `ros2 multicast receive` / `ros2 multicast send` | Any |
