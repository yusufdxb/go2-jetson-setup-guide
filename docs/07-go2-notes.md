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

The GO2 EDU provides a power output for external compute devices. The exact voltage and connector are documented in Unitree's hardware manual for your firmware version — obtain this from Unitree's support portal before wiring anything.

As a general reference from community reports, the payload rail is in the 24V range, but **measure with a multimeter before connecting**. Your Jetson carrier board likely expects a different voltage:

| Jetson Setup | Expected Input Voltage |
|-------------|----------------------|
| Orin NX/Nano on a third-party carrier board | Check your carrier board's datasheet — commonly 12V or 19V |
| Orin NX/Nano Developer Kit (NVIDIA) | 9–20V via barrel jack |
| Orin Nano Developer Kit (NVIDIA) | 5V via USB-C (up to 25W) |

You will likely need a **DC-DC converter** (buck converter) to step down to whatever your carrier board expects. Size it for at least 30W to handle the Orin NX's 25W peak draw plus converter losses.

### During Initial Setup

**Use a separate power supply** (wall adapter) to power the Jetson while you
are setting up software and testing. This eliminates power-related variables
when debugging. Only switch to the GO2's power output after everything is
working.

---

## Communicating with the GO2

### Unitree SDKs

Unitree provides two main SDKs:

- **unitree_legged_sdk** — C++ library for sending commands and receiving state over UDP. Does not depend on ROS 2.
- **unitree_ros2** — ROS 2 wrapper around the SDK, providing GO2 state and control over standard ROS 2 topics and services.

Both communicate with the GO2 main board over UDP on the `192.168.123.x` network.

**Installing ROS 2 alone does not make GO2 topics appear.** You must separately clone, build, and configure `unitree_ros2` (or the base SDK) before you will see robot-specific topics from `ros2 topic list`. Start here: https://github.com/unitreerobotics/unitree_ros2

### Control Levels

The GO2 supports two levels of control:

**High-level control** (start here):
- Send velocity commands: walk forward/backward, strafe, turn
- The GO2's internal controller handles gait, balance, and foot placement
- Lower risk than low-level control, but the robot will still walk, which means it can fall off surfaces, walk into obstacles, or tip over on uneven terrain
- Always test with the robot on a flat, clear surface with no drop-offs nearby
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

4. **The GO2 has built-in protection features.** According to Unitree's
   documentation, the firmware may cut motor power if it detects abnormal
   commands (excessive torque, impossible joint angles). However, do not rely
   on this as a safety guarantee — protection thresholds may vary by firmware
   version, and a fall can still cause damage to the robot or surroundings.

5. **If the robot starts behaving unexpectedly**, try these in order (none are
   guaranteed to work in every situation — always keep a safe distance):
   - Press the power button once — on most firmware versions, this triggers a
     sit-down sequence, but behavior may vary by firmware
   - Use the emergency stop on the remote controller if available
   - As a last resort, hold the power button for several seconds to force a
     hard shutdown — the robot will collapse without a controlled sit-down
   - If your code is the problem, Ctrl+C the process on the Jetson — note that
     the robot may continue its last command briefly until the control loop
     times out

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
| GO2 LiDAR (if present) | varies | Scan the network to discover — see tip below |
| GO2 Cameras (if present) | varies | Scan the network to discover — see tip below |

> **Tip:** You can scan the network to discover all active devices:
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
