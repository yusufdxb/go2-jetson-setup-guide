# 02 -- Flash the Jetson

This page walks you through flashing JetPack onto your Jetson Orin NX or Orin Nano. Do this **on your desk**, before mounting anything on the GO2.

---

## Prerequisites

| What | Details |
|------|---------|
| **Laptop** | Running Ubuntu 20.04 or 22.04 (native install, not a VM -- USB passthrough in VMs causes flash failures). Ubuntu 18.04 also works for SDK Manager but 22.04 is recommended. |
| **USB-C data cable** | Connects your laptop to the Jetson carrier board's USB-C flashing port. Must support data transfer -- cheap charge-only cables will not work. |
| **Jetson module seated on a carrier board** | Module firmly clicked into the SODIMM slot. |
| **Power supply for the Jetson** | USB-C PD (65 W+) or barrel jack, depending on your carrier board. |
| **Internet connection on the laptop** | SDK Manager downloads several GB of packages. |
| **Free disk space on the laptop** | At least **40 GB** free. SDK Manager downloads and unpacks large images. |

---

## Step 1: Download NVIDIA SDK Manager

**[Laptop]**

Go to: https://developer.nvidia.com/sdk-manager

You will need a free NVIDIA Developer account. Create one if you don't have one.

Download the `.deb` package for Ubuntu (it will be named something like `sdkmanager_*_amd64.deb`).

---

## Step 2: Install SDK Manager

**[Laptop]**

```bash
cd ~/Downloads
sudo dpkg -i sdkmanager_*_amd64.deb
```

If there are missing dependencies, fix them:

```bash
sudo apt-get install -f -y
```

**Verification:**

```bash
sdkmanager --version
```

**Expected output:**

```
NVIDIA SDK Manager version X.X.X.XXXX
```

**If this fails...**
- Make sure you are running a 64-bit Ubuntu install (`uname -m` should print `x86_64`).
- If `dpkg` complains about missing libraries, run `sudo apt-get install -f -y` and try again.
- SDK Manager does not run on ARM laptops. You need an x86_64 machine.

---

## Step 3: Put the Jetson into Recovery Mode

**[Jetson]** (physically, at your desk)

The Jetson must be in "USB recovery mode" so your laptop can see it as a flashable device. The exact button layout depends on your carrier board, but the general process is:

### NVIDIA DevKit carrier board

1. Make sure the Jetson is **powered off** (disconnect power).
2. Locate the **recovery button** (small tactile button, usually labeled `REC` or `FC REC`).
3. Locate the **power button** (labeled `PWR`).
4. Connect the **USB-C data cable** from your laptop to the Jetson's USB-C flashing port.
5. **Hold the recovery button down.**
6. While still holding recovery, **connect power** (or press the power button if power is already connected).
7. Wait 2 seconds, then **release the recovery button**.

The Jetson screen will stay black -- that is normal. It is now in recovery mode.

### Third-party carrier boards

Check your carrier board's documentation. The recovery process is usually similar but button locations differ. Some boards have jumper pins instead of buttons.

---

## Step 4: Verify Recovery Mode

**[Laptop]**

```bash
lsusb
```

**Expected output** (look for a line containing `NVIDIA`):

```
Bus 001 Device 004: ID 0955:7523 NVIDIA Corp. APX
```

The vendor ID `0955` confirms it is an NVIDIA device in recovery mode. The product ID may vary (e.g., `7523`, `7e19`, etc.) depending on the exact Orin variant.

**If you don't see an NVIDIA device...**
- Try a different USB-C cable (this is the most common problem).
- Try a different USB port on your laptop (USB 3.0 ports work best; avoid USB hubs).
- Redo the recovery mode sequence -- timing matters.
- Make sure the Jetson has power.

---

## Step 5: Launch SDK Manager and Flash

**[Laptop]**

```bash
sdkmanager
```

SDK Manager opens a graphical interface. Log in with your NVIDIA Developer account.

### Step 5a: Select target hardware

- Under **Target Hardware**, select your module:
  - `Jetson Orin NX 16GB` or
  - `Jetson Orin Nano 8GB`
  - (Select the one that matches the module you have.)
- SDK Manager should auto-detect the connected Jetson. If not, make sure recovery mode is active (Step 4).

### Step 5b: Select JetPack version

- Choose the latest **JetPack 6.x** release.
- It will show the underlying L4T (Linux for Tegra) version -- that is fine, you don't need to choose L4T separately.

### Step 5c: Select components

At minimum, select:

- **Jetson Linux** (the base OS image) -- required
- **Jetson Runtime Components** -- required
- **Jetson SDK Components** (CUDA, cuDNN, TensorRT, etc.) -- recommended

You can install SDK components later over the network if you want a faster initial flash. But it is easiest to install everything now.

### Step 5d: Review and flash

- Click **Continue** / **Next**.
- SDK Manager will download the packages (this can take 15-30 minutes depending on your internet speed).
- It will ask you to confirm the flash. Select **Manual Setup** if prompted about the connection mode.
- Choose to flash the **entire Jetson** (not just update).
- The flash process takes approximately **10-20 minutes**. Do **not** unplug the USB cable or power during this time.

**Expected output in SDK Manager:**

A progress bar showing the flash stages. When complete, it will say something like:

```
Flash - successful
```

### Step 5e: SDK components install (if selected)

After flashing the OS, SDK Manager may ask for the Jetson's IP address and login credentials to install SDK components (CUDA, etc.) over the network. At this point:

1. The Jetson will reboot and boot into Ubuntu for the first time.
2. You need to complete the Ubuntu first-boot setup on the Jetson (see [03 -- First Boot](03-first-boot.md)) **before** SDK Manager can SSH in to install components.
3. Once the Jetson is booted and you have created a user, enter the Jetson's IP and credentials in SDK Manager.

Alternatively, skip this step in SDK Manager and install components manually later using `sudo apt install nvidia-jetpack`.

---

## Alternative: Command-Line Flash (Advanced)

If you prefer not to use SDK Manager's GUI, you can flash from the command line. This is useful for headless servers or scripted setups.

**[Laptop]**

```bash
# Download and extract the L4T BSP and root filesystem from NVIDIA's developer site.
# The exact filenames change with each release. Check:
# https://developer.nvidia.com/linux-tegra

# Example for a hypothetical JetPack 6.x release:
# TODO: update these filenames to match the actual latest JetPack 6.x release
cd ~/Downloads
tar xf Jetson_Linux_R36.*_aarch64.tbz2
cd Linux_for_Tegra/rootfs/
sudo tar xpf ../../Tegra_Linux_Sample-Root-Filesystem_R36.*_aarch64.tbz2
cd ..
sudo ./apply_binaries.sh
```

Then flash (with the Jetson in recovery mode):

```bash
# For Jetson Orin NX on DevKit carrier board:
sudo ./flash.sh jetson-orin-nx-devkit-16gb internal

# For Jetson Orin Nano on DevKit carrier board:
sudo ./flash.sh jetson-orin-nano-devkit internal
```

<!-- TODO: verify the exact board config names (jetson-orin-nx-devkit-16gb, etc.) for the latest L4T release. Run `ls flash.sh` configs to check. -->

**If the flash fails...**
- Check `lsusb` again to make sure the Jetson is still in recovery mode.
- Read the error output carefully -- common issues are: wrong board config name, insufficient disk space, USB disconnect.
- Try a shorter, higher-quality USB-C cable.
- If you see "USB transfer error," try a USB 2.0 port instead of USB 3.0 (counterintuitively, USB 2.0 is sometimes more reliable for flashing).

---

## Step 6: Verify the Flash

**[Jetson]**

After a successful flash, the Jetson will reboot automatically. If you have a monitor connected:

1. You should see the NVIDIA boot logo.
2. Then the Ubuntu 22.04 first-boot setup (language selection, user creation, etc.).

If you see the Ubuntu setup screen, the flash was successful.

**If the Jetson does not boot...**
- Reconnect power and press the power button.
- If you get a black screen with no NVIDIA logo, the flash may have failed. Re-enter recovery mode and try flashing again.
- Check that the Jetson module is firmly seated in the carrier board's SODIMM slot.

---

## Important Note

Flash and test the Jetson **before** mounting it on the GO2. Recovery mode requires pressing small buttons on the carrier board that are difficult or impossible to reach once the Jetson is inside the robot's payload bay.

---

## Next Step

Proceed to [03 -- First Boot and Initial Configuration](03-first-boot.md).
