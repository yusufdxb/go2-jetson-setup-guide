# 06: Installing ROS 2 on the Jetson

## Why ROS 2?

The Unitree GO2 community and Unitree's own SDK increasingly rely on ROS 2 for
robot control, perception, and navigation. ROS 2 (Robot Operating System 2)
gives you a standard way to:

- Send movement commands to the GO2
- Read sensor data (cameras, LiDAR, IMU)
- Run SLAM, navigation, and perception pipelines
- Communicate between the Jetson, your laptop, and the GO2 over the network

This guide recommends ROS 2 for GO2 development. ROS 2 is required if you
want to use Unitree's `unitree_ros2` package or integrate with the broader
ROS ecosystem. However, if you only need direct motor control or sensor
access, Unitree's `unitree_legged_sdk` (C++ UDP) works without ROS 2.

## Which Version?

**ROS 2 Humble Hawksbill**: this is the Long Term Support (LTS) release,
supported through 2027. It targets **Ubuntu 22.04**, which is what JetPack 6.x
ships with.

> **Note:** If your JetPack version uses Ubuntu 20.04 instead of 22.04, you
> would need ROS 2 Foxy or Galactic. JetPack 6.x should be 22.04. You can
> check with:
> ```
> # [Jetson]
> lsb_release -a
> ```
> Look for `Release: 22.04`.

---

## Installation Steps

All commands in this section run on **[Jetson]**.

### Step 1: Set Locale

ROS 2 requires a UTF-8 locale.

```bash
# [Jetson]
sudo apt update && sudo apt install locales
sudo locale-gen en_US en_US.UTF-8
sudo update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
export LANG=en_US.UTF-8
```

**Verify:**

```bash
# [Jetson]
locale
```

You should see `LANG=en_US.UTF-8` in the output.

---

### Step 2: Add the ROS 2 Apt Repository

```bash
# [Jetson]
sudo apt install software-properties-common
sudo add-apt-repository universe
```

```bash
# [Jetson]
sudo curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
  -o /usr/share/keyrings/ros-archive-keyring.gpg
```

```bash
# [Jetson]
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
  http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
  | sudo tee /etc/apt/sources.list.d/ros2.list > /dev/null
```

**Verify:**

```bash
# [Jetson]
cat /etc/apt/sources.list.d/ros2.list
```

Expected output (on a Jetson with JetPack 6.x):

```
deb [arch=arm64 signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] http://packages.ros.org/ros2/ubuntu jammy main
```

**If this fails...**
- If `curl` is not installed: `sudo apt install curl`
- If you see `arch=amd64` instead of `arch=arm64`, something is wrong with
  your JetPack install, the Jetson is an ARM device and should report `arm64`.

---

### Step 3: Install ROS 2 Humble

```bash
# [Jetson]
sudo apt update
sudo apt install ros-humble-desktop -y
```

This will download roughly **2 GB** of packages and take a while. Be patient.

> **Lighter alternative:** If you do not need GUI tools (RViz, rqt, etc.), you
> can install `ros-humble-ros-base` instead. This is significantly smaller but
> means you will need to visualize data from your laptop rather than the Jetson.
>
> ```bash
> # [Jetson] (alternative, pick one or the other, not both)
> sudo apt install ros-humble-ros-base -y
> ```

**If this fails...**
- `E: Unable to locate package ros-humble-desktop`: the apt repository was
  not added correctly. Go back to Step 2.
- Hash sum mismatch, run `sudo apt clean` and try again.

---

### Step 4: Install Development Tools

```bash
# [Jetson]
sudo apt install python3-colcon-common-extensions python3-rosdep python3-argcomplete -y
```

These give you:
- `colcon`: the ROS 2 build tool
- `rosdep`: automatically installs dependencies for ROS packages
- `argcomplete`: tab-completion for ROS 2 CLI commands

---

### Step 5: Initialize rosdep

```bash
# [Jetson]
sudo rosdep init
rosdep update
```

**If this fails...**
- `ERROR: default sources list file already exists`: this means `rosdep init`
  was already run once. This is fine. Just run `rosdep update`.

---

### Step 6: Source ROS 2 in Your Shell

```bash
# [Jetson]
echo "source /opt/ros/humble/setup.bash" >> ~/.bashrc
source ~/.bashrc
```

This makes ROS 2 commands available every time you open a terminal.

---

## Verification

Run these commands to confirm everything is working.

### Check ROS 2 CLI

```bash
# [Jetson]
ros2 --help
```

Expected output: a help message listing ROS 2 subcommands (`action`, `bag`,
`topic`, `node`, etc.).

### Check Default Topics

```bash
# [Jetson]
ros2 topic list
```

Expected output:

```
/parameter_events
/rosout
```

### Quick Talker/Listener Test

Open **two** SSH sessions (or two terminals) on the Jetson.

**Terminal 1:**

```bash
# [Jetson]
ros2 run demo_nodes_cpp talker
```

**Terminal 2:**

```bash
# [Jetson]
ros2 run demo_nodes_cpp listener
```

Expected output in Terminal 2:

```
[INFO] [listener]: I heard: [Hello World: 1]
[INFO] [listener]: I heard: [Hello World: 2]
[INFO] [listener]: I heard: [Hello World: 3]
...
```

Press `Ctrl+C` in both terminals to stop.

**If this fails...**
- `command not found: ros2`: your shell is not sourcing the setup file. Run
  `source /opt/ros/humble/setup.bash` and check your `~/.bashrc`.
- `Package 'demo_nodes_cpp' not found`: you installed `ros-humble-ros-base`
  instead of `ros-humble-desktop`. Install the demo package separately:
  `sudo apt install ros-humble-demo-nodes-cpp`

---

## What ROS 2 Alone Does NOT Do

Installing ROS 2 gets you the middleware and tooling. It does **not** automatically make GO2 robot topics appear. After this guide, running `ros2 topic list` will show only the default topics (`/parameter_events`, `/rosout`) unless you have nodes publishing data.

To communicate with the GO2, you additionally need **one of**:

- **[unitree_ros2](https://github.com/unitreerobotics/unitree_ros2)**: Unitree's official ROS 2 package that wraps the Unitree SDK and exposes GO2 state and control over ROS 2 topics/services. This requires building from source in your workspace.
- **unitree_legged_sdk**: The lower-level C++ UDP SDK. Does not require ROS 2 but has no ROS integration out of the box.

The setup for `unitree_ros2` is outside the scope of this guide. Start with the [unitree_ros2 GitHub repository](https://github.com/unitreerobotics/unitree_ros2) and its README after completing the steps here. Verify basic ROS 2 communication (talker/listener below) before moving on to the Unitree stack.

---

## Workspace Setup

A ROS 2 workspace is where you put your own packages and any packages you
build from source (like the Unitree SDK).

```bash
# [Jetson]
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws
colcon build
source install/setup.bash
```

The first `colcon build` on an empty workspace is fast, it just sets up the
directory structure.

Add the workspace to your shell so it loads automatically:

```bash
# [Jetson]
echo "source ~/ros2_ws/install/setup.bash" >> ~/.bashrc
```

> **Important:** The workspace source line must come **after** the
> `/opt/ros/humble/setup.bash` line in your `~/.bashrc`. Since we added
> the ROS 2 line first, this ordering is correct.

---

## DDS and Networking

ROS 2 uses DDS (Data Distribution Service) as its communication middleware.
By default, it uses **multicast** on the local network to discover other
ROS 2 nodes. This is how the Jetson and your laptop can see each other's
topics without any manual configuration.

### ROS_DOMAIN_ID

All ROS 2 nodes with the same `ROS_DOMAIN_ID` can see each other. The default
is `0`. As long as both machines use the same ID, they will communicate:

```bash
# [Jetson] and [Laptop]: add to ~/.bashrc on both machines
export ROS_DOMAIN_ID=0
```

### If Multicast Does Not Work

The GO2's internal network (192.168.123.x) may not support multicast. If
`ros2 topic list` on your laptop cannot see topics published by the Jetson
(or vice versa), you need to switch to **unicast** using Cyclone DDS.

**Install Cyclone DDS:**

```bash
# [Jetson]
sudo apt install ros-humble-rmw-cyclonedds-cpp -y
```

```bash
# [Laptop] (if your laptop also runs ROS 2 Humble)
sudo apt install ros-humble-rmw-cyclonedds-cpp -y
```

**Set the RMW implementation** (add to `~/.bashrc` on both machines):

```bash
export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
```

**Create a Cyclone DDS config file** for unicast peer discovery:

```bash
# [Jetson]
mkdir -p ~/cyclonedds
cat << 'EOF' > ~/cyclonedds/cyclonedds.xml
<?xml version="1.0" encoding="UTF-8" ?>
<CycloneDDS xmlns="https://cdds.io/config">
  <Domain>
    <General>
      <AllowMulticast>false</AllowMulticast>
    </General>
    <Discovery>
      <ParticipantIndex>auto</ParticipantIndex>
      <Peers>
        <!-- List all machines running ROS 2 nodes -->
        <Peer address="192.168.123.15"/>   <!-- Jetson -->
        <Peer address="192.168.123.100"/>  <!-- Laptop -->
        <!-- Do NOT add 192.168.123.161 here unless you have confirmed
             that a ROS 2 / DDS node is running on the GO2 main board.
             The GO2 main board uses Unitree's own UDP protocol by default,
             not DDS. -->
      </Peers>
    </Discovery>
  </Domain>
</CycloneDDS>
EOF
```

Copy the same file to your laptop and any other machine on the network.

**Point Cyclone DDS to the config** (add to `~/.bashrc`):

```bash
export CYCLONEDDS_URI=file:///home/$USER/cyclonedds/cyclonedds.xml
```

After adding these environment variables, open a new terminal (or
`source ~/.bashrc`) for them to take effect.

---

## Debug Commands Reference

These commands are useful when things are not working as expected.

```bash
# [Jetson] or [Laptop]

# List all active topics
ros2 topic list

# See messages being published on a specific topic
ros2 topic echo /topic_name

# List all active ROS 2 nodes
ros2 node list

# Check ROS 2 system health (network, middleware, etc.)
ros2 doctor

# Test whether multicast works on this network
ros2 multicast receive
# (In another terminal, run: ros2 multicast send)

# Show detailed info about a topic (type, publishers, subscribers)
ros2 topic info /topic_name --verbose

# Check which DDS implementation is active
echo $RMW_IMPLEMENTATION
# (blank means the default: Fast DDS)
```

---

**Next:** [07, GO2 Notes and Safety](07-go2-notes.md)
