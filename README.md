# FPV Robot Car — Raspberry Pi WiFi Controller

A WiFi-controlled FPV robot car built on a Raspberry Pi 4. The car streams live video over a local network and is controlled through a web interface that works on any phone or laptop browser with no app install required. The backend is Python and Flask, the motor control uses gpiozero, and the camera stream uses picamera2.

The web UI was designed with AI assistance to achieve a cyberpunk HUD aesthetic — the logic, hardware integration, debugging, and overall system architecture were all done manually.

---

## Demo
<img width="1915" height="927" alt="image" src="https://github.com/user-attachments/assets/b6200476-a613-458b-9f9a-9bc6da20e860" />
<img width="1918" height="931" alt="image" src="https://github.com/user-attachments/assets/569db87c-3b04-490c-b968-632c0ac98e51" />
<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/9f01ab80-94d5-4a56-a9ec-acf2d14f44d4" />
<img width="1536" height="2048" alt="image" src="https://github.com/user-attachments/assets/7d2da9b8-7418-4838-9383-adccf69c07e5" />
<img width="1536" height="2048" alt="image" src="https://github.com/user-attachments/assets/6fbf4f9d-7f4d-43b9-84c4-7e4af1bc83f3" />
<img width="2048" height="1536" alt="image" src="https://github.com/user-attachments/assets/e4b43427-a0bf-41e9-b2c5-a097c06fe3e0" />
<img width="1033" height="863" alt="image" src="https://github.com/user-attachments/assets/3d9d42e2-c9df-4ffa-b2c3-2a7a15771934" />


---

## Features

- Live MJPEG camera stream via picamera2, viewable in any browser on the local network
- Cyberpunk HUD web interface — scanlines, neon glow, corner brackets, crosshair, direction indicator
- Mobile virtual joystick via NippleJS with configurable dead zone
- WASD keyboard control with proper hold detection and no repeat firing
- Speed slider — adjustable PWM duty cycle in real time
- Boost mode — temporary speed burst, auto-cancels after 2.5 seconds
- Emergency stop button and Escape key shortcut
- Digital zoom — buttons, scroll wheel, or pinch-to-zoom on mobile
- Watchdog — automatically stops motors if the connection is lost for more than 1 second
- Auto-connects on page load, no IP entry required
- Reboot and shutdown buttons in the interface
- Systemd service auto-starts the app on every boot
- One-command setup script installs and configures everything automatically

---

## Parts List

### Core Components

| Part | Recommended Model | Notes |
|---|---|---|
| Single board computer | Raspberry Pi 4 (2GB or 4GB) | Any Pi 4 with a CSI camera port |
| MicroSD card | SanDisk Ultra 32GB or Samsung Evo Plus 32GB | Avoid cheap unbranded cards — they corrupt easily under repeated writes |
| Camera module | Any IMX219-based module (Pi Camera v2, Arducam IMX219, Pibiger PI-CAMV2) | Must be IMX219 sensor for this config. See camera section for other sensors |
| Motor driver | L298N dual H-bridge | Any compatible dual H-bridge will work |
| DC motors | JZK TT motors or equivalent | 4x for 4WD chassis |
| Robot chassis | Any 4WD or 2WD chassis kit | Must have enough space to mount Pi and electronics |

### Power System

| Part | Recommended Model | Notes |
|---|---|---|
| Battery | 3S 11.1V LiPo, 2200mAh or higher, 25C or higher | Higher C rating gives better motor response |
| Battery charger | Any balance charger compatible with 3S LiPo (e.g. ISDT Q6 Plus) | Always balance charge LiPo batteries — never charge unattended |
| Battery connector | XT60 extension cable (cut the male end off) | Used as the main power input connector for easy battery swaps |
| Buck converter | LM2596 or XL4016 adjustable DC-DC step-down module | Set output to exactly 5.1V before connecting to Pi |
| Pi power cable | USB-C pigtail cable | Cut open and wire 5V and GND to buck converter output |
| Power switch | Inline rocker or toggle switch rated 15A or higher | Wired in series on the positive line from battery |

### Optional Additions

| Part | Notes |
|---|---|
| LiPo battery alarm | Plugs into balance lead, beeps when voltage drops below 3.5V per cell. Prevents over-discharge |
| MOSFET (IRLZ44N) + 1k resistor | Required if adding GPIO-controlled LED lights |
| HC-SR04 ultrasonic sensor | For future obstacle detection |
| Heatsink kit for Pi 4 | Recommended if running the stream continuously for long sessions |

---

## Flashing the SD Card

### Step 1 — Download Raspberry Pi Imager

Go to https://www.raspberrypi.com/software and download Raspberry Pi Imager for your operating system. Install and open it.

### Step 2 — Choose the OS

Click "Choose OS" and select:
- Raspberry Pi OS (other) → Raspberry Pi OS Lite (64-bit)

Use Lite — it has no desktop and runs faster, which matters for the camera stream.

### Step 3 — Choose your SD card

Insert your microSD card. Click "Choose Storage" and select your card. Make sure you select the correct drive — this process wipes everything on it.

### Step 4 — Configure settings before flashing

Click the settings gear icon (or press Ctrl+Shift+X) and fill in the following:

- Set hostname: (any name you prefer — this is what you will SSH into)
- Enable SSH: checked, use password authentication
- Set username: pi
- Set password: choose a strong password
- Configure WiFi: enter your home WiFi name and password
- Set locale: set your timezone and keyboard layout

These settings are applied automatically on first boot so you do not need a monitor or keyboard to set up the Pi.

### Step 5 — Flash the card

Click Write. Imager will download the OS, write it to the card, and verify it. This takes around 5 to 10 minutes. Do not remove the card until it says it is complete.

### Step 6 — Insert the card and power on

Put the SD card into the Pi. Connect power. Wait about 60 seconds for the first boot to complete.

### Step 7 — Find the Pi on your network

From your PC, open Command Prompt and try:

```
ping (name of pi).local
```

If it responds, the Pi is online. If not, wait another 30 seconds and try again. If it still does not respond, log into your router (usually at 192.168.1.1) and look for a device called wisdompi in the connected devices list to find its IP address.

### Step 8 — SSH into the Pi

```
ssh pi@(name of pi).local
```

Type yes when asked about the fingerprint, then enter your password. You are now connected and ready to run the setup script.

---

## Setting a Static IP Address

A static IP ensures the Pi always gets the same address so the web interface URL never changes.

### Step 1 — Find your router gateway

On Windows run:
```
ipconfig
```
Look for Default Gateway — usually 192.168.1.1 or 192.168.0.1.

### Step 2 — SSH into the Pi and edit dhcpcd

```bash
sudo nano /etc/dhcpcd.conf
```

### Step 3 — Add these lines at the bottom

```
interface wlan0
static ip_address=192.168.1.XXX/24
static routers=192.168.1.1
static domain_name_servers=8.8.8.8
```

Replace XXX with a number that is:
- On the same subnet as your router (e.g. 192.168.1.XXX if your gateway is 192.168.1.1)
- Outside your router's DHCP range — check your router settings. DHCP usually assigns from .100 to .200, so pick something like .50 or .250

### Step 4 — Save and reboot

Press Ctrl+O, Enter, then Ctrl+X to save. Then:

```bash
sudo reboot
```

After reboot, use your chosen static IP in place of (name of pi).local in all commands and in the MIT App Inventor HomeURL.

---

## Setup

### One-Command Install

After flashing the OS, SSHing in, and optionally setting a static IP, upload and run the setup script:

```bash
# On your Windows PC — upload the script
scp setup.sh pi@wisdompi.local:~/setup.sh

# SSH in and run it
ssh pi@(name of pi).local
sudo apt install dos2unix -y
dos2unix setup.sh
bash setup.sh
```

The script does the following in order:
Update system packages
Install Python dependencies (RPi.GPIO, picamera2, Flask)
Enable camera overlay — removes duplicates first, then adds once
Disable WiFi power saving — both NetworkManager config AND interface level via rc.local
Set the GPIO pin factory in .bashrc
Create all project files in order: app.py → index.html → motor_test.py
Create and enable the systemd service
Verify all files exist and print a summary before rebooting

After reboot, open a browser on any device on the same network and go to:

```
http://(name of pi).local:5000
```

or use your static IP if you set one:

```
http://YOUR_STATIC_IP:5000
```

### If You Change the Folder Name or Location

The setup script uses ~/robot_car as the default folder. If you move or rename it, update the systemd service:

```bash
sudo nano /etc/systemd/system/robotcar.service
```

Change these two lines:
```
WorkingDirectory=/home/pi/YOUR_FOLDER_NAME
ExecStart=/usr/bin/python3 /home/pi/YOUR_FOLDER_NAME/app.py
```

Then reload:
```bash
sudo systemctl daemon-reload
sudo systemctl restart robotcar
```

---

## File Paths

| File | Path |
|---|---|
| Flask backend | /home/pi/robot_car/app.py |
| Web interface | /home/pi/robot_car/templates/index.html |
| Motor test script | /home/pi/robot_car/motor_test.py |
| Systemd service | /etc/systemd/system/robotcar.service |
| Camera overlay config | /boot/firmware/config.txt |
| WiFi power saving config | /etc/NetworkManager/conf.d/wifi-powersave-off.conf |

---

## Wiring

### Motor Driver to Raspberry Pi 4 GPIO

| Function | Default GPIO | Notes |
|---|---|---|
| Left motor PWM enable | GPIO 12 | Hardware PWM — do not change to another pin |
| Right motor PWM enable | GPIO 13 | Hardware PWM — do not change to another pin |
| Left motor forward | GPIO 17 | Configurable in app.py |
| Left motor backward | GPIO 23 | Configurable in app.py |
| Right motor forward | GPIO 27 | Configurable in app.py |
| Right motor backward | GPIO 22 | Configurable in app.py |
| GND | Any Pi GND pin | Must share ground with Pi |

GPIO 12 and 13 are used specifically because they support hardware PWM on the Pi 4. Changing them to other pins will cause a PWMUnsupported error.

### Changing GPIO Pins

Edit these lines in app.py:

```python
ena = PWMOutputDevice(12)   # ENA — must be a hardware PWM pin
enb = PWMOutputDevice(13)   # ENB — must be a hardware PWM pin

left_motors  = Motor(forward=17, backward=23)
right_motors = Motor(forward=27, backward=22)
```

### Camera

| Setting | Value |
|---|---|
| Connection | CSI ribbon cable to Pi camera port |
| Config required | dtoverlay=imx219 in /boot/firmware/config.txt |
| Ribbon cable orientation | Blue side facing USB-A ports on the Pi |

Using a different sensor? Replace imx219 with your sensor name. Common alternatives: imx477 for HQ Camera, ov5647 for Pi Camera v1.

---

## Motor Direction

Depending on how your motors are wired, the car may drive in the wrong direction.

### Car goes backward when it should go forward

Swap forward and backward for both motors in app.py:

```python
left_motors  = Motor(forward=23, backward=17)
right_motors = Motor(forward=22, backward=27)
```

You can also fix this by physically swapping the motor wires on the L298N output terminals.

### Car spins in circles instead of going straight

One motor is wired in reverse. Swap only the affected side:

```python
# If left motor is reversed
left_motors  = Motor(forward=23, backward=17)   # swapped
right_motors = Motor(forward=27, backward=22)   # unchanged

# If right motor is reversed
left_motors  = Motor(forward=17, backward=23)   # unchanged
right_motors = Motor(forward=22, backward=27)   # swapped
```

### Left and right are swapped

Swap the entire left and right motor assignments:

```python
left_motors  = Motor(forward=27, backward=22)   # was right
right_motors = Motor(forward=17, backward=23)   # was left
```

---

## Motor Speed Cap

Always set a safe PWM cap for your motors. Running at full voltage for long periods can cause overheating and burnout.

This project caps normal operation at 70% PWM with boost mode allowed up to 90% for 2.5 second bursts only.

To adjust for your motors, edit these lines in app.py:

```python
ena.value = 0.7   # 70% — adjust to suit your motors
enb.value = 0.7

speed = min(speed, 0.9)   # 90% max including boost
```

If your motors are rated 3-12V and your battery is 11.1V, starting at 60-70% is a safe baseline.

---

## Power Wiring

### Overview

The LiPo powers two things: the Pi via a buck converter, and the L298N motor driver directly. A single XT60 connector is used as the main power input for quick battery swaps.

### Wiring the XT60 Input

Take an XT60 extension cable and cut the male plug end off. Strip the wires (red = positive, black = negative). Wire the positive wire through the power switch so the switch cuts all power when off.

### Wiring the Buck Converter

Connect the battery positive (after the switch) to buck converter IN+ and battery negative to IN-. Before connecting anything to the output, power on and use a multimeter to adjust the potentiometer until the output reads exactly 5.1V. Cut open a USB-C pigtail cable, identify the 5V (red) and GND (black) wires, connect them to buck converter OUT+ and OUT-, and plug the USB-C end into the Pi.

### Wiring the L298N

Connect L298N 12V input to battery positive (after the switch) and L298N GND to battery negative. The L298N GND must also connect to a Pi GND GPIO pin so they share a common ground.

### Power Flow Summary

```
Battery (+) → Switch → splits into:
    Path 1: Buck Converter IN+ → OUT+ → USB-C → Pi (5.1V)
    Path 2: L298N 12V input (11.1V direct)

Battery (-) → Buck Converter IN- and L298N GND (shared)
L298N GND → Pi GND pin (shared ground)
```

### Swapping Batteries

1. Flip the switch off
2. Unplug the XT60
3. Plug in a charged battery
4. Flip the switch on

Never unplug the XT60 while the switch is on — it causes arcing on the connector.

---

## Using MIT App Inventor (Android)

### Step 1 — Create a project

Go to https://appinventor.mit.edu, sign in, and click Start new project.

### Step 2 — Set up the screen

Select Screen1. In the Properties panel set:
- ScreenOrientation: Landscape
- Sizing: Responsive

### Step 3 — Add a WebViewer

From the User Interface palette, drag a WebViewer onto the screen. Set:
- Width: Fill parent
- Height: Fill parent
- ScrollableHorizontal: unchecked
- ScrollableVertical: unchecked
- HomeURL: http://YOUR_PI_IP:5000

### Step 4 — Add a cache-clearing block

In the Blocks view add:

```
when Screen1.Initialize
  call WebViewer1.ClearCaches
  set WebViewer1.HomeURL to "http://YOUR_PI_IP:5000"
  call WebViewer1.GoHome
```

### Step 5 — Build and install

Click Build → App (provide QR code for .apk). Scan with the MIT AI2 Companion app or download the APK directly.

### Step 6 — Use it

Open the app on your phone. Make sure you are on the same WiFi network as the Pi. The interface loads automatically.

---

## System Architecture

```
+-----------------------------------------------------+
|                  LOCAL NETWORK (WiFi)               |
|                                                     |
|   +--------------+         +---------------------+  |
|   |   Phone /    | HTTP    |   Raspberry Pi 4    |  |
|   |   Laptop     |<------->|   Flask :5000       |  |
|   |   Browser    |         |                     |  |
|   +--------------+         |  +---------------+  |  |
|                            |  |  picamera2    |  |  |
|                            |  |  MJPEG stream |  |  |
|                            |  +-------+-------+  |  |
|                            |          |           |  |
|                            |  +-------v-------+  |  |
|                            |  |  gpiozero     |  |  |
|                            |  |  GPIO control |  |  |
|                            +--+-------+-------+--+  |
+------------------------------------------+----------+
                                           | GPIO
                                  +--------v--------+
                                  |  Motor Driver   |
                                  |  (e.g. L298N)   |
                                  +--------+--------+
                                           |
                                  +--------v--------+
                                  |   DC Motors     |
                                  +-----------------+
```

---

## Full Stack

| Layer | Technology |
|---|---|
| Compute | Raspberry Pi 4 |
| Camera | IMX219-based CSI module |
| Motor driver | L298N dual H-bridge |
| Backend | Python 3 / Flask |
| GPIO library | gpiozero with RPi.GPIO pin factory |
| Camera library | picamera2 with MJPEGEncoder |
| Frontend logic | Vanilla JavaScript |
| Joystick | NippleJS |
| UI design | HTML/CSS — designed with AI assistance |
| Fonts | Orbitron + Share Tech Mono via Google Fonts |

---

## Problems Solved

### 1. Hardware PWM on Enable Pins

**Problem:** gpiozero's Motor() class only takes 2 direction pins. Passing a third for the enable pin throws TypeError: Motor.__init__() takes 3 positional arguments but 4 were given.

**Solution:** Control the enable pins separately using PWMOutputDevice on GPIO 12 and 13. Direction goes to Motor(), speed goes to PWMOutputDevice.

---

### 2. GPIO Busy Error on Boot

**Problem:** On Raspberry Pi OS Bookworm, gpiozero defaults to the lgpio pin factory which conflicts with hardware PWM on GPIO 12 and 13, throwing lgpio.error: GPIO busy.

**Solution:** Force gpiozero to use RPi.GPIO by setting the environment variable before any imports:

```python
import os
os.environ['GPIOZERO_PIN_FACTORY'] = 'rpigpio'
```

Also set in the systemd service Environment= directive so it applies on auto-start.

---

### 3. Camera Not Detected After Reflash

**Problem:** The IMX219 overlay is not enabled by default. After every reflash picamera2 throws IndexError: list index out of range on boot because the camera is not detected.

**Solution:** Add dtoverlay=imx219 to /boot/firmware/config.txt. The setup script removes duplicates first then adds it once cleanly.

---

### 4. WiFi Disconnections

**Problem:** The Pi's WiFi adapter enters power saving mode after a few minutes and drops the connection.

**Solution:** Two-layer fix — disable via NetworkManager config and also via iwconfig at boot through rc.local:

```
# /etc/NetworkManager/conf.d/wifi-powersave-off.conf
[connection]
wifi.powersave = 2
```

```bash
# In /etc/rc.local before exit 0
iwconfig wlan0 power off
```

---

### 5. Flask Blocking on Camera Stream

**Problem:** Flask's single-threaded server blocks when the MJPEG stream is active, preventing the main page from loading.

**Solution:** Enable threaded mode with app.run(threaded=True). The stream runs in its own thread via a threading.Condition buffer.

---

### 6. Motors Keep Running After Disconnect

**Problem:** If the WiFi drops mid-drive, the last move command stays active and the car continues moving until manually stopped.

**Solution:** A watchdog thread runs in the background and checks the time since the last /move request. If no command arrives within 1 second, both motors are stopped automatically.

```python
def watchdog():
    while True:
        if time.time() - last_command_time > 1.0:
            left_motors.stop()
            right_motors.stop()
        time.sleep(0.2)
```

---

### 7. Joystick Sensitivity and Key Repeat

**Problem:** The NippleJS joystick fires commands from very small movements. Holding a keyboard key fires repeated keydown events, spamming the Pi with requests.

**Solution:** NippleJS threshold: 0.5 and data.force > 0.5 create a dead zone. The keyboard handler uses if (e.repeat) return to block repeats, and a Set tracks held keys so multi-key combinations work correctly.

---

## Project Structure

```
robot_car/
    app.py                  Flask backend — motors, camera, routes, watchdog
    templates/
        index.html          Web interface — cyberpunk HUD, joystick, controls
    motor_test.py           Standalone motor test — run before first use

setup.sh                    One-command setup script
```

---

## Roadmap

- Gesture controller using ESP32 and MPU6050 hand tilt unit
- Ultrasonic obstacle detection with HC-SR04
- Servo camera pan and tilt mount
- GPIO-controlled LED headlights via MOSFET
- LiDAR ROS2 integration
- Encoder-based odometry

---

## Contributing

Pull requests welcome. If you adapt this for a different motor driver, camera sensor, or chassis, feel free to open a PR adding your wiring configuration to the README.

---

## Author

Built by a robotics and software engineering student at UTC Derby

Wisdom Daramola.

Hardware integration, motor control, system debugging, and architecture done manually.
Web UI aesthetics designed with AI assistance.

---

## Licence

MIT — free to use, modify and build on.
