# 05 - Internet Sharing

## The Problem

The Jetson is connected to the GO2's internal `192.168.123.x` network, which has no internet access. But you need internet on the Jetson to install packages (`apt`, `pip`), clone repos (`git`), and download models.

## The Solution

Use your laptop as a gateway. Your laptop already has internet (over Wi-Fi or another connection). You can configure it to forward the Jetson's traffic out to the internet and send the responses back.

```
Jetson  ---->  192.168.123.x network  ---->  Laptop  ---->  Internet
                                              (NAT)
```

---

## Recommended Method: NAT / IP Forwarding from Laptop

This is the simplest and most reliable approach. Your laptop acts as a router for the Jetson.

### Assumptions

Before starting, identify your laptop's network interfaces:

```bash
# [Laptop]
ip addr show
```

You need to know two interfaces:

| Interface | Description | Example names |
|-----------|-------------|---------------|
| **Internet-facing** | The interface your laptop uses for internet (usually Wi-Fi) | `wlan0`, `wlp2s0` |
| **Jetson-facing** | The Ethernet interface connected to the GO2/Jetson | `eth0`, `enp3s0` |

> In the commands below, we use `wlan0` for internet and `eth0` for the Jetson-facing interface. **Replace these with your actual interface names.**

### Step 1: Enable IP Forwarding on the Laptop

By default, Linux does not forward packets between network interfaces. Turn it on:

```bash
# [Laptop]
sudo sysctl -w net.ipv4.ip_forward=1
```

**Verify:**

```bash
# [Laptop]
cat /proc/sys/net/ipv4/ip_forward
```

**Expected output:**

```
1
```

> **If this shows `0`...** The sysctl command did not work. Try running it again with `sudo`.

### Step 2: Set Up NAT with iptables on the Laptop

These three rules tell your laptop how to handle the Jetson's traffic:

```bash
# [Laptop]
sudo iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
```

**What this does:** When traffic from the Jetson leaves through `wlan0` (your internet interface), rewrite the source address to look like it came from the laptop. This is called "masquerading" -- it hides the Jetson behind the laptop's IP so the internet can send replies back.

```bash
# [Laptop]
sudo iptables -A FORWARD -i eth0 -o wlan0 -j ACCEPT
```

**What this does:** Allow traffic coming in from `eth0` (the Jetson side) to be forwarded out through `wlan0` (the internet side). Without this, the laptop would just drop the Jetson's packets.

```bash
# [Laptop]
sudo iptables -A FORWARD -i wlan0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

**What this does:** Allow return traffic (responses from the internet) to come back through `wlan0` and be forwarded to `eth0` (back to the Jetson). The `RELATED,ESTABLISHED` part means it only allows responses to connections the Jetson started -- it does not open the Jetson to random incoming connections from the internet.

### Step 3: Set the Default Gateway and DNS on the Jetson

Tell the Jetson to send all internet-bound traffic to your laptop, and configure DNS for domain name resolution. Both settings are stored in the `go2-network` connection profile so they persist across reboots:

```bash
# [Jetson] Set the laptop as the default gateway (persistent)
sudo nmcli con mod go2-network ipv4.gateway 192.168.123.100

# [Jetson] Set DNS servers (persistent)
sudo nmcli con mod go2-network ipv4.dns "8.8.8.8 8.8.4.4"

# [Jetson] Apply the changes
sudo nmcli con up go2-network
```

> `192.168.123.100` is your laptop's IP on the GO2 network (set in the previous guide). The DNS line uses Google's public DNS — you can substitute `1.1.1.1 1.0.0.1` for Cloudflare instead.

**Verify the gateway:**

```bash
# [Jetson]
ip route show
```

**Expected output** (look for the `default` line):

```
default via 192.168.123.100 dev eth0 proto static metric 100
192.168.123.0/24 dev eth0 proto kernel scope link src 192.168.123.15
```

**Verify DNS is configured:**

```bash
# [Jetson]
nmcli con show go2-network | grep -E "ipv4.gateway|ipv4.dns"
```

> On JetPack 6.x (Ubuntu 22.04), `/etc/resolv.conf` is managed by `systemd-resolved` and NetworkManager. Do not write directly to `/etc/resolv.conf` — your changes will be overwritten. The `nmcli` method above persists correctly.

> **If `nmcli con up` fails with a route conflict...** Another connection may already have a default route set. Check with `nmcli con show --active` and deactivate any conflicting connections. You can also check the current default route with `ip route show default`.

### Step 4: Verify Internet Access on the Jetson

Run these three tests in order. Each one tests a different layer:

```bash
# [Jetson] Test 1: Raw IP connectivity (does traffic reach the internet?)
ping -c 3 8.8.8.8
```

**Expected output:**

```
64 bytes from 8.8.8.8: icmp_seq=1 ttl=115 time=12.3 ms
...
3 packets transmitted, 3 received, 0% packet loss
```

```bash
# [Jetson] Test 2: DNS resolution (can it look up domain names?)
ping -c 3 google.com
```

```bash
# [Jetson] Test 3: Full HTTPS (can it download things?)
curl -s https://httpbin.org/ip
```

**Expected output:**

```json
{
  "origin": "your.public.ip.address"
}
```

If all three work, the Jetson has full internet access. You can now run `sudo apt update`, `pip install`, `git clone`, etc.

---

## Important: Persistence Across Reboots

The **Jetson side** (gateway and DNS) is already persistent — those settings are stored in the `go2-network` NetworkManager profile and survive reboots automatically.

The **laptop side** (iptables rules and IP forwarding) is **not persistent** by default. They will be lost when you reboot your laptop.

### Quick fix: Re-run the commands

After each laptop reboot, re-run Steps 1 and 2 on the laptop. The Jetson does not need reconfiguration.

### Better fix: Use iptables-persistent

```bash
# [Laptop]
sudo apt install iptables-persistent
```

During installation it will ask if you want to save current rules -- say **Yes**.

To save rules again later:

```bash
# [Laptop]
sudo netfilter-persistent save
```

You will still need to make IP forwarding persistent. Add this line to `/etc/sysctl.conf` on the laptop:

```
net.ipv4.ip_forward=1
```

### Best fix: Use the helper script

The `scripts/share_internet_from_laptop.sh` script sets up everything in one command. It validates your interface names, avoids adding duplicate rules, and prints the exact commands to run on the Jetson:

```bash
# [Laptop]
sudo ./scripts/share_internet_from_laptop.sh <internet_iface> <jetson_iface>
# Example:
sudo ./scripts/share_internet_from_laptop.sh wlan0 eth0
```

To remove the rules:

```bash
# [Laptop]
sudo ./scripts/share_internet_from_laptop.sh --clean wlan0 eth0
```

---

## Advanced / Optional: SOCKS Proxy via SSH Tunnel

> This section is for advanced users. Skip this if the NAT method above worked for you.

In some environments (corporate networks, restricted setups), you may not be able to set up NAT on the laptop. An alternative is to create an SSH tunnel that the Jetson uses as a proxy.

### Set up the tunnel

```bash
# [Jetson]
ssh -D 1080 -N laptop-user@192.168.123.100
```

This creates a SOCKS5 proxy on the Jetson at `localhost:1080` that tunnels traffic through the laptop.

- `-D 1080` -- open a SOCKS proxy on port 1080
- `-N` -- do not open a shell, just hold the tunnel open
- Replace `laptop-user` with your laptop's username

### Use the proxy with common tools

**curl:**

```bash
# [Jetson]
curl --proxy socks5h://localhost:1080 https://httpbin.org/ip
```

**apt** via an HTTP proxy tunnel (more reliable for apt than SOCKS):

Instead of a SOCKS proxy, create an HTTP proxy with port forwarding:

```bash
# [Jetson] — forward local port 8080 to the laptop's squid/http proxy if available
# Or use the SOCKS proxy with apt via:
echo 'Acquire::http::Proxy "socks5h://localhost:1080";' | sudo tee /etc/apt/apt.conf.d/99proxy
```

> apt's SOCKS proxy support depends on the version. If apt downloads fail through the proxy, the NAT method in the main section is more reliable.

**pip:**

```bash
# [Jetson]
pip install --proxy socks5h://localhost:1080 some-package
```

**git:**

```bash
# [Jetson]
git config --global http.proxy socks5h://localhost:1080
```

> This approach is more complex and fragile than NAT. Every tool needs separate proxy configuration, and the SSH tunnel must stay open. Use NAT if you can.

---

## Advanced / Optional: USB Wi-Fi Adapter on Jetson

If you want the Jetson to have its own independent internet connection, you can plug a USB Wi-Fi adapter directly into it.

### Step 1: Plug in the adapter and check detection

```bash
# [Jetson]
lsusb
```

Look for your Wi-Fi adapter in the list.

```bash
# [Jetson]
nmcli device status
```

If the adapter is detected and has a driver, you should see a new `wifi` device (e.g., `wlan0`).

### Step 2: Scan for networks

```bash
# [Jetson]
nmcli device wifi list
```

### Step 3: Connect

```bash
# [Jetson]
nmcli device wifi connect "YOUR_WIFI_SSID" password "YOUR_WIFI_PASSWORD"
```

### Step 4: Verify

```bash
# [Jetson]
ping -c 3 google.com
```

> **Important:** Not all USB Wi-Fi adapters work on the Jetson. The Jetson runs an ARM-based Linux kernel and many consumer Wi-Fi adapters do not have ARM drivers. Check the [NVIDIA Jetson forums](https://forums.developer.nvidia.com/c/agx-autonomous-machines/jetson-embedded-systems/) for adapter compatibility lists before purchasing one.

> This approach gives the Jetson its own internet without relying on the laptop. However, it adds another piece of hardware and you still need the `192.168.123.x` Ethernet connection for communicating with the GO2.

---

## Troubleshooting

### "ping 8.8.8.8 works but ping google.com does not"

This is a DNS issue. The Jetson can reach the internet but cannot resolve domain names.

**Fix:**

On JetPack 6.x (Ubuntu 22.04), `/etc/resolv.conf` is typically managed by `systemd-resolved` via NetworkManager. Do **not** write to `/etc/resolv.conf` directly — your changes will be overwritten on the next reboot or network event.

Instead, configure DNS through NetworkManager:

```bash
# [Jetson]
sudo nmcli con mod go2-network ipv4.dns "8.8.8.8 8.8.4.4"
sudo nmcli con up go2-network
```

**Verify:**

```bash
# [Jetson]
resolvectl status
```

Look for your DNS servers listed under the Ethernet interface section. Then test:

```bash
# [Jetson]
ping -c 3 google.com
```

### "No route to host" from Jetson when pinging external IPs

The default gateway is not set on the Jetson.

**Fix:**

```bash
# [Jetson]
ip route show
```

If there is no `default via ...` line, set the gateway in the connection profile:

```bash
# [Jetson]
sudo nmcli con mod go2-network ipv4.gateway 192.168.123.100
sudo nmcli con up go2-network
```

### "Laptop lost its own internet after setting up NAT"

You likely used the wrong interface name in the iptables rules. If you accidentally masquerade on the Jetson-facing interface instead of the internet-facing one, things will break.

**Fix:** Remove only the rules you added (do **not** flush the entire chain — that can break Docker, VMs, and other services that also use iptables):

```bash
# [Laptop] Remove the specific rules that were added incorrectly.
# Replace <wrong_iface> with whatever you mistakenly used.
sudo iptables -t nat -D POSTROUTING -o <wrong_iface> -j MASQUERADE
sudo iptables -D FORWARD -i <wrong_iface> -o <other_iface> -j ACCEPT
sudo iptables -D FORWARD -i <other_iface> -o <wrong_iface> -m state --state RELATED,ESTABLISHED -j ACCEPT
```

If you used the helper script, run `--clean` with the same interfaces you originally passed:

```bash
# [Laptop]
sudo ./scripts/share_internet_from_laptop.sh --clean <wrong_inet_iface> <wrong_jetson_iface>
```

Then re-run the iptables commands from Step 2 with the correct interface names. Double-check with:

```bash
# [Laptop]
nmcli device status
```

Make sure `wlan0` (or whatever you used in the `-o` flag) is your actual internet interface.

### "Connection refused" when setting up SSH tunnel (SOCKS proxy method)

Make sure your laptop's SSH server is running:

```bash
# [Laptop]
sudo systemctl status ssh
```

If it is not running:

```bash
# [Laptop]
sudo apt install openssh-server
sudo systemctl enable --now ssh
```

> On Ubuntu, the SSH service is named `ssh`, not `sshd`. Some other distributions use `sshd`.

---

## Summary

At this point you should have:

- [x] Internet access on the Jetson (via laptop NAT, Wi-Fi adapter, or proxy)
- [x] Ability to run `apt update`, `pip install`, and `git clone` on the Jetson
- [x] Understanding of how to re-enable internet sharing after a reboot

Next up: installing ROS 2 and other software on the Jetson.
