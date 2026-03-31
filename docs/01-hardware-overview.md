# 01 -- Hardware Overview

This guide walks you through adding an NVIDIA Jetson to a Unitree GO2 quadruped robot. Before touching any cables, read this page so you understand what hardware is involved and how the pieces connect.

---

## What You Need

| Item | Notes |
|------|-------|
| **Unitree GO2** (EDU or PRO) | The EDU version ships with a more accessible internal network. The PRO version works too, but some default IPs may differ -- check Unitree's docs for your firmware version. |
| **NVIDIA Jetson Orin NX 16 GB** or **Jetson Orin Nano 8 GB** | Either module works. The Orin NX has more GPU cores and RAM, which matters for heavier perception workloads. Both use the same carrier board form factor. |
| **Jetson carrier board** | Most people use the NVIDIA DevKit carrier board or a third-party board (Seeed reComputer, Auvidea, etc.). Make sure the carrier board matches your module. |
| **Laptop** | Ubuntu 20.04 or 22.04 recommended. You will use this to flash the Jetson and, later, to SSH into both the Jetson and the GO2. |
| **Ethernet cable (x2)** | One to connect your laptop to the GO2's external Ethernet port during setup. One to connect the Jetson to the GO2's internal Ethernet network. |
| **USB-C cable** | Used to put the Jetson in recovery mode and flash it from your laptop. Must support data (not a charge-only cable). |
| **Power for the Jetson** | During initial setup (before mounting on the robot), use a USB-C PD adapter (65 W or higher) or the barrel jack that came with your carrier board. |
| **Monitor, keyboard, mouse** | For the Jetson's first boot only. After SSH is set up you won't need these. |

---

## The GO2's Internal Computer

The GO2 already has onboard compute. Depending on the model:

- **GO2 EDU**: ships with a Jetson Orin NX or Orin Nano inside. Yes, there is already a Jetson in the dog. The one you are adding is a *second* compute unit -- typically used for custom perception or autonomy workloads.
- **GO2 PRO**: ships with a less powerful internal board.

<!-- TODO: confirm exact board model for GO2 PRO (some sources say RK3588) -->

The GO2's main control board (the MCU that handles motor control, IMU, and the stock locomotion controller) sits on the internal Ethernet network regardless of model. Your Jetson will join that same network.

---

## Internal Network Layout

The GO2 uses a wired Ethernet network inside the body with the subnet **192.168.123.0/24**. The key addresses:

| Device | Typical IP |
|--------|-----------|
| Main control board (MCU) | `192.168.123.161` |
| Built-in Jetson (EDU) or internal board (PRO) | `192.168.123.13` or `.15` |
| Your new Jetson (what we will set up) | `192.168.123.15` (we assign this later) |
| GO2's Wi-Fi AP gateway | `192.168.12.1` (different subnet -- this is the Wi-Fi, not the wired network) |

<!-- TODO: double-check default IP for built-in Jetson on EDU -- some firmware versions use .13, others .15. If there is already a .15 device, pick .18 or another unused address. -->

> **Important**: If your GO2 EDU already has an internal Jetson at `192.168.123.15`, choose a different IP for your new Jetson (e.g., `192.168.123.18`). You can scan the network later with `nmap -sn 192.168.123.0/24` to see what is already taken.

---

## Network Diagram

```
                         ┌──────────────────────────────────┐
                         │         Unitree GO2 Body         │
                         │                                  │
  [Your Laptop]          │  ┌──────────────┐                │
  192.168.123.x ─────────┼──┤  Ethernet    │                │
  (Ethernet or Wi-Fi)    │  │  Switch      │                │
                         │  │  (internal)  │                │
                         │  └──┬───┬───┬───┘                │
                         │     │   │   │                    │
                         │     │   │   │                    │
                         │     ▼   │   ▼                    │
                         │  ┌─────┐│┌──────────────────┐    │
                         │  │ MCU ││ │ Your New Jetson  │    │
                         │  │.161 ││ │ .15 (or .18)    │    │
                         │  └─────┘│ └──────────────────┘   │
                         │         │                        │
                         │         ▼                        │
                         │  ┌──────────────┐                │
                         │  │ Built-in     │                │
                         │  │ Compute      │                │
                         │  │ .13 (EDU)    │                │
                         │  └──────────────┘                │
                         │                                  │
                         │  All on subnet 192.168.123.0/24  │
                         └──────────────────────────────────┘
```

Everything on the 192.168.123.x subnet can talk to everything else. The MCU at `.161` exposes the robot's control API (LCM or DDS topics, depending on firmware).

---

## JetPack Version

Target **JetPack 6.x** (the latest 6.x release available when you do the setup). JetPack 6.x is based on:

- **Ubuntu 22.04** (Jammy)
- **CUDA 12.x**
- **cuDNN 9.x**
- **TensorRT 10.x**

JetPack 6.x is required for Orin NX and Orin Nano modules. Older JetPack 5.x releases do not support Orin.

You can check the latest available version at: https://developer.nvidia.com/jetpack-sdk

---

## Power Considerations

The Jetson Orin NX draws up to **25 W** at full load. The Orin Nano draws up to **15 W**.

### During initial setup (on your desk)

Use one of these:

- **USB-C PD adapter** (65 W recommended) connected to the carrier board's USB-C port.
- **Barrel jack power supply** (the NVIDIA DevKit carrier board takes a 19 V DC barrel jack -- check your carrier board's specs).

Do **not** try to power the Jetson from the GO2 during initial flashing and setup. Flash it on your desk with its own power supply.

### After mounting on the GO2

The GO2's internal battery provides a **24 V rail** that can power additional hardware. Options:

1. **Tap the internal 24 V rail** through the GO2's payload power connector and use a DC-DC converter to step it down to the voltage your carrier board expects (usually 5 V or 19 V depending on the board).
2. **Use a separate battery** mounted on the GO2's back (some people strap on a small LiPo or USB-C power bank).

<!-- TODO: add specific connector part number for GO2 internal payload power output -->

> **Warning**: Incorrect voltage will destroy the Jetson. Always verify the voltage with a multimeter before connecting.

---

## Physical Mounting

This guide does not cover mechanical mounting in detail since every setup is different. A few tips:

- Mount the Jetson on the **top payload bay** of the GO2. Unitree sells mounting plates, and many people 3D-print custom brackets.
- Route the Ethernet cable through the GO2's existing cable channels if possible.
- Keep the Jetson's heatsink/fan unobstructed -- it needs airflow.
- Secure all cables with zip ties or cable clips. The GO2 moves violently and loose cables will disconnect or snag.
- Flash and fully configure the Jetson **before** mounting it on the robot. Accessing recovery mode buttons is much harder once it is inside the dog.

---

## Next Step

Proceed to [02 -- Flash the Jetson](02-flash-jetson.md).
