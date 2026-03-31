# 07 — GO2 Notes, Safety, and Communication

This document covers what you need to know about the Unitree GO2 itself before
you start sending commands from the Jetson.

---

## GO2 Internal Architecture

The GO2 has its own internal computer (main control board) running Unitree's
proprietary firmware. You do not modify or reflash this board — you communicate
with it over Ethernet.

Key facts:

- **Internal network:** `192.168.123.x`
- **Main board IP:** `192.168.123.161` (this is standard across GO2 units)
- The main board runs internal services on various ports for motor control,
  sensor data, and state reporting
- **DO NOT change any IPs on the GO2 main board.** Doing so can break internal
  communication between the robot's subsystems.

Your Jetson connects to this network and talks to the main board as a peer on
the same subnet.

---

## GO2 Models

Not all GO2 models support external compute. Here is what differs:

| Model | External Compute | Notes |
|-------|-----------------|-------|
| **GO2 Air** | No | Consumer model. No expansion port for a Jetson. |
| **GO2 PRO** | Limited | Has an expansion port. Can connect a Jetson, but SDK support is limited. |
| **GO2 EDU** | Yes | Designed for development. Has a dedicated Ethernet port for external compute, official Unitree SDK support, and a power output for peripherals. |

If you are following this guide, you most likely have a **GO2 EDU**. The PRO
can work but may require extra steps not covered here.

---

## Mounting the Jetson

The Jetson is typically mounted on the GO2's back (dorsal) surface.

- **GO2 EDU** comes with a mounting plate or mounting points for accessories
- For other models, a **3D-printed bracket** is commonly used (search the
  Unitree community for STL files)
- **Keep cables tidy.** Loose cables dangling from the Jetson can get caught in
  the GO2's legs during walking. Use zip ties or cable clips.
- Make sure the **Ethernet cable** from the Jetson reaches the GO2's internal
  Ethernet port without pulling tight when the robot moves

---

## Power

### GO2 EDU Power Output

The GO2 EDU provides a power output (typically **24V**) for external compute
devices. However, your Jetson carrier board likely expects a different voltage:

| Jetson Setup | Expected Input Voltage |
|-------------|----------------------|
| Orin NX/Nano on a third-party carrier board | Typically 12V or 19V (check your carrier board datasheet) |
| Orin Nano Developer Kit | 5V via USB-C (up to 25W), or DC barrel jack |

<!-- TODO: verify exact power output voltage and connector on GO2 EDU -->
<!-- TODO: verify power requirements for your specific carrier board -->

You will likely need a **DC-DC converter** (buck converter) to step the GO2's
24V output down to whatever your carrier board expects. Make sure the converter
can handle the current draw — the Orin NX can pull up to 25W under load.

### During Initial Setup

**Use a separate power supply** (wall adapter) to power the Jetson while you
are setting up software and testing. This eliminates power-related variables
when debugging. Only switch to the GO2's power output after everything is
working.

---

## Communicating with the GO2

### Unitree SDKs

Unitree provides two main SDKs:

- **unitree_legged_sdk** — C++ library for sending commands and receiving state
  over UDP
- **unitree_ros2** — ROS 2 wrapper around the SDK, providing standard ROS 2
  topics and services

Both communicate with the GO2 main board over UDP on the `192.168.123.x`
network.

### Control Levels

The GO2 supports two levels of control:

**High-level control** (start here):
- Send velocity commands: walk forward/backward, strafe, turn
- The GO2's internal controller handles gait, balance, and foot placement
- Safe for beginners — the robot will not do anything destructive
- Example: "walk forward at 0.3 m/s"

**Low-level control** (advanced):
- Direct control of each motor (position, velocity, torque)
- Bypasses the GO2's internal balance controller
- **Can damage the robot** if commands are wrong — motors can overheat, legs
  can collide, the robot can fall violently

> **SAFETY: Always start with high-level control.** Do not attempt low-level
> control until you fully understand the SDK and have tested extensively on a
> stand.

### Basic Connectivity Test

Before running any SDK code, verify you can reach the GO2:

```bash
# [Jetson]
ping 192.168.123.161
```

Expected output:

```
PING 192.168.123.161 (192.168.123.161) 56(84) bytes of data.
64 bytes from 192.168.123.161: icmp_seq=1 ttl=64 time=0.5 ms
64 bytes from 192.168.123.161: icmp_seq=2 ttl=64 time=0.4 ms
```

**If this fails...**
- Check that the Ethernet cable is connected between the Jetson and the GO2
- Check that the Jetson's IP is set to `192.168.123.15` (see the networking
  guide)
- Check that the GO2 is powered on and has finished booting (wait 30+ seconds
  after power-on)
- Try `ip addr show` on the Jetson to confirm the Ethernet interface has the
  correct IP

---

## Safety Notes

Read this section carefully before running any code on the GO2.

1. **Always test on a stand first.** Place the GO2 on an elevated surface or
   robot stand so its legs cannot touch the ground. This way, if your code
   sends unexpected commands, the robot flails in the air instead of launching
   itself across the room.

2. **Keep the emergency stop remote nearby.** The GO2 comes with a remote
   controller. Know where the emergency stop button is before you start.

3. **Never run untested low-level motor commands with the robot on the ground.**
   A bad torque command can cause a leg to slam down or the robot to flip.

4. **The GO2 has built-in protection mode.** If it detects abnormal motor
   commands (excessive torque, impossible joint angles), it will cut motor
   power and collapse. This protects the hardware but can still result in a
   fall.

5. **If the robot starts behaving unexpectedly:**
   - Press the power button once to make it sit down
   - Use the emergency stop on the remote
   - As a last resort, hold the power button to force shutdown
   - If your code is the problem, Ctrl+C the process on the Jetson

6. **Do not stand directly over the robot** while testing. Stand to the side.
   A sudden leg movement can strike you.

7. **Battery awareness.** If the GO2's battery gets low during testing, it will
   start behaving sluggishly and may sit down on its own. Keep it charged.

---

## IP Address Reference

Use this table as a quick reference for the devices on the GO2 network.

| Device | IP Address | Notes |
|--------|-----------|-------|
| GO2 Main Board | `192.168.123.161` | Do not change. Standard across all GO2 units. |
| Jetson (recommended) | `192.168.123.15` | Set in netplan (see networking guide) |
| Laptop (recommended) | `192.168.123.100` | Set on your Ethernet interface |
| GO2 LiDAR (if present) | `192.168.123.x` | Varies by model and configuration |
| GO2 Cameras (if present) | `192.168.123.x` | Varies by model and configuration |

<!-- TODO: fill in exact LiDAR and camera IPs for GO2 EDU if available -->

> **Tip:** You can scan the network to discover devices:
> ```bash
> # [Jetson]
> sudo apt install nmap -y
> nmap -sn 192.168.123.0/24
> ```
> This will show all active devices on the GO2 network.

---

## Useful Unitree Resources

- **Unitree Support/Docs:** <https://support.unitree.com/> (official starting
  point; note that documentation pages may move or be reorganized over time)
- **Unitree GitHub (SDKs, ROS packages):** <https://github.com/unitreerobotics>
- **Community forums and Discord servers** exist for Unitree robot owners. Search
  for "Unitree GO2" on Discord or Reddit to find active communities.
  <!-- Not linking specific community URLs since they change frequently -->

---

**Previous:** [06 — ROS 2 Bootstrap](06-ros2-bootstrap.md)
