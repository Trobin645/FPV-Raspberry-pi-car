#!/bin/bash
# ============================================
# WISDOMBOT ROBOT CAR - FULL SETUP SCRIPT
# Run with: bash setup.sh
# ============================================

echo ""
echo "======================================"
echo "  WISDOMBOT SETUP - STARTING"
echo "======================================"
echo ""

# Step 1 - Update system
echo "[1/8] Updating system..."
sudo apt update -y && sudo apt upgrade -y

# Step 2 - Install dependencies
echo "[2/8] Installing dependencies..."
sudo apt install python3-rpi.gpio python3-picamera2 -y
pip3 install flask --break-system-packages

# Step 3 - Enable camera overlay
echo "[3/8] Enabling camera..."
# Remove any duplicate entries first
sudo sed -i '/dtoverlay=imx219/d' /boot/firmware/config.txt
# Add it once cleanly
echo "dtoverlay=imx219" | sudo tee -a /boot/firmware/config.txt

# Step 4 - Fix WiFi power saving
echo "[4/8] Disabling WiFi power saving..."
sudo mkdir -p /etc/NetworkManager/conf.d
echo -e "[connection]\nwifi.powersave = 2" | sudo tee /etc/NetworkManager/conf.d/wifi-powersave-off.conf
sudo systemctl restart NetworkManager 2>/dev/null || true

# Step 5 - Set GPIO pin factory
echo "[5/8] Setting GPIO factory..."
# Remove existing entry if present
sed -i '/GPIOZERO_PIN_FACTORY/d' ~/.bashrc
echo "export GPIOZERO_PIN_FACTORY=rpigpio" >> ~/.bashrc

# Step 6 - Create robot folder and files
echo "[6/8] Creating robot car files..."
mkdir -p ~/robot_car/templates

# Write app.py
cat > ~/robot_car/app.py << 'PYEOF'
import os
os.environ['GPIOZERO_PIN_FACTORY'] = 'rpigpio'

from flask import Flask, render_template, request, Response
from gpiozero import Motor, PWMOutputDevice
from picamera2 import Picamera2
from picamera2.encoders import MJPEGEncoder
from picamera2.outputs import FileOutput
import io
import threading
import time

app = Flask(__name__)

# Enable pins for PWM speed control
ena = PWMOutputDevice(12)
enb = PWMOutputDevice(13)

# Motor direction pins
left_motors  = Motor(forward=17, backward=23)
right_motors = Motor(forward=27, backward=22)

# 70% PWM cap
ena.value = 0.7
enb.value = 0.7

# Camera resolutions
RESOLUTIONS = {
    'low':  {'size': (640, 480),   'sensor': (640, 480)},
    'med':  {'size': (1280, 720),  'sensor': (1640, 1232)},
    'high': {'size': (1640, 1232), 'sensor': (3280, 2464)},
}
current_res = 'low'

camera = Picamera2()

def configure_camera(res_key):
    global camera, stream_output
    res = RESOLUTIONS[res_key]
    try:
        camera.stop_recording()
    except Exception:
        pass
    camera.configure(camera.create_video_configuration(
        main={"size": res['size']},
        sensor={"output_size": res['sensor'], "bit_depth": 10}
    ))
    stream_output = StreamOutput()
    camera.start_recording(MJPEGEncoder(), FileOutput(stream_output))

class StreamOutput(io.BufferedIOBase):
    def __init__(self):
        self.frame = None
        self.condition = threading.Condition()

    def write(self, buf):
        with self.condition:
            self.frame = buf
            self.condition.notify_all()

stream_output = StreamOutput()
configure_camera(current_res)

def generate_frames():
    while True:
        with stream_output.condition:
            stream_output.condition.wait()
            frame = stream_output.frame
        yield (b'--frame\r\nContent-Type: image/jpeg\r\n\r\n' + frame + b'\r\n')

# Watchdog
last_command_time = time.time()
WATCHDOG_TIMEOUT = 0.5

def watchdog():
    while True:
        if time.time() - last_command_time > WATCHDOG_TIMEOUT:
            left_motors.stop()
            right_motors.stop()
        time.sleep(0.1)

watchdog_thread = threading.Thread(target=watchdog, daemon=True)
watchdog_thread.start()

@app.route('/stream')
def stream():
    return Response(generate_frames(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/move')
def move():
    global last_command_time
    last_command_time = time.time()
    direction = request.args.get('dir')
    speed = min(float(request.args.get('speed', 0.6)), 0.9)
    if direction == 'up':
        left_motors.forward(speed); right_motors.forward(speed)
    elif direction == 'down':
        left_motors.backward(speed); right_motors.backward(speed)
    elif direction == 'left':
        left_motors.backward(speed); right_motors.forward(speed)
    elif direction == 'right':
        left_motors.forward(speed); right_motors.backward(speed)
    else:
        left_motors.stop(); right_motors.stop()
    return "OK"

@app.route('/resolution')
def resolution():
    global current_res
    res = request.args.get('res', 'low')
    if res in RESOLUTIONS and res != current_res:
        current_res = res
        t = threading.Thread(target=configure_camera, args=(res,), daemon=True)
        t.start()
    return current_res

@app.route('/power')
def power():
    action = request.args.get('action')
    if action == 'shutdown':
        os.system("sudo shutdown -h now"); return "Shutting down..."
    elif action == 'reboot':
        os.system("sudo reboot"); return "Rebooting..."
    return "Invalid Action"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
PYEOF

# Write index.html
cat > ~/robot_car/templates/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/nipplejs/0.10.1/nipplejs.min.js"></script>
    <link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@400;700;900&display=swap" rel="stylesheet">
    <style>
        :root { --neon: #00ffe7; --neon2: #ff003c; --dark: #000d0d; --border: rgba(0,255,231,0.3); }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { background: var(--dark); overflow: hidden; font-family: 'Share Tech Mono', monospace; cursor: crosshair; }
        body::before { content: ''; position: fixed; inset: 0; background: repeating-linear-gradient(0deg, transparent, transparent 2px, rgba(0,0,0,0.15) 2px, rgba(0,0,0,0.15) 4px); pointer-events: none; z-index: 100; }
        body::after { content: ''; position: fixed; inset: 0; background: radial-gradient(ellipse at center, transparent 50%, rgba(0,0,0,0.8) 100%); pointer-events: none; z-index: 99; }
        #camera-feed { position: fixed; top: 0; left: 0; width: 100%; height: 100%; object-fit: cover; z-index: 1; opacity: 0.85; filter: saturate(0.8) contrast(1.1); transform-origin: center center; transition: transform 0.15s ease; }
        .corner { position: fixed; width: 36px; height: 36px; z-index: 20; pointer-events: none; }
        .corner::before, .corner::after { content: ''; position: absolute; background: var(--neon); box-shadow: 0 0 8px var(--neon); }
        .corner::before { width: 100%; height: 2px; }
        .corner::after { width: 2px; height: 100%; }
        .corner.tl { top: 10px; left: 10px; }
        .corner.tr { top: 10px; right: 10px; transform: scaleX(-1); }
        .corner.bl { bottom: 10px; left: 10px; transform: scaleY(-1); }
        .corner.br { bottom: 10px; right: 10px; transform: scale(-1); }
        #crosshair-wrap { position: fixed; top: 50%; left: 50%; transform: translate(-50%,-50%); width: 40px; height: 40px; z-index: 20; pointer-events: none; }
        #crosshair-wrap.cross::before,
        #crosshair-wrap.cross::after { content: ''; position: absolute; background: var(--neon); box-shadow: 0 0 6px var(--neon); opacity: 0.6; }
        #crosshair-wrap.cross::before { width: 100%; height: 1px; top: 50%; left: 0; }
        #crosshair-wrap.cross::after { width: 1px; height: 100%; left: 50%; top: 0; }
        #crosshair-wrap.dot::before { content: ''; position: absolute; width: 6px; height: 6px; border-radius: 50%; background: var(--neon); box-shadow: 0 0 8px var(--neon); top: 50%; left: 50%; transform: translate(-50%,-50%); opacity: 0.8; }
        #crosshair-wrap.circle::before { content: ''; position: absolute; width: 30px; height: 30px; border-radius: 50%; border: 1px solid var(--neon); box-shadow: 0 0 8px var(--neon); top: 50%; left: 50%; transform: translate(-50%,-50%); opacity: 0.6; }
        #crosshair-wrap.target::before { content: ''; position: absolute; width: 30px; height: 30px; border-radius: 50%; border: 1px solid var(--neon); top: 50%; left: 50%; transform: translate(-50%,-50%); opacity: 0.6; }
        #crosshair-wrap.target::after { content: ''; position: absolute; width: 1px; height: 100%; background: var(--neon); left: 50%; top: 0; opacity: 0.5; box-shadow: 0 0 4px var(--neon); }
        #crosshair-wrap.target .ch-h { position: absolute; height: 1px; width: 100%; background: var(--neon); top: 50%; left: 0; opacity: 0.5; box-shadow: 0 0 4px var(--neon); }
        #crosshair-wrap.none { display: none; }
        #move-flash { position: fixed; inset: 0; pointer-events: none; z-index: 5; border: 2px solid transparent; transition: border-color 0.1s; }
        #move-flash.active { border-color: rgba(0,255,231,0.15); }
        #top-bar { position: fixed; top: 0; left: 0; right: 0; height: 48px; z-index: 30; display: flex; align-items: center; justify-content: space-between; padding: 0 12px; gap: 8px; background: rgba(0,13,13,0.85); border-bottom: 1px solid rgba(0,255,231,0.15); backdrop-filter: blur(6px); }
        #top-left { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }
        #top-centre { display: flex; align-items: center; gap: 8px; flex: 1; justify-content: center; }
        #top-right { display: flex; align-items: center; gap: 6px; flex-shrink: 0; }
        .top-btn { background: transparent; border: 1px solid var(--border); color: rgba(0,255,231,0.6); font-family: 'Share Tech Mono', monospace; font-size: 8px; letter-spacing: 1px; padding: 5px 8px; cursor: crosshair; text-transform: uppercase; transition: all 0.2s; white-space: nowrap; flex-shrink: 0; border-radius: 2px; }
        .top-btn:hover { color: var(--neon); border-color: var(--neon); box-shadow: 0 0 8px rgba(0,255,231,0.2); }
        .top-btn.active-mode { color: var(--neon); border-color: var(--neon); box-shadow: 0 0 10px rgba(0,255,231,0.3); }
        #hud-title { font-family: 'Orbitron', monospace; font-weight: 900; font-size: 10px; letter-spacing: 4px; color: var(--neon); text-shadow: 0 0 12px var(--neon); white-space: nowrap; }
        .hud-dot { width: 5px; height: 5px; border-radius: 50%; background: var(--neon); box-shadow: 0 0 6px var(--neon); animation: blink 1.4s infinite; flex-shrink: 0; }
        @keyframes blink { 0%,100%{opacity:1} 50%{opacity:0.2} }
        .ctrl-group { display: flex; align-items: center; gap: 5px; background: rgba(0,255,231,0.04); border: 1px solid rgba(0,255,231,0.2); padding: 4px 8px; border-radius: 3px; flex-shrink: 0; }
        .ctrl-label { font-family: 'Orbitron', monospace; font-size: 6px; letter-spacing: 2px; color: rgba(0,255,231,0.4); text-transform: uppercase; }
        .ctrl-val { font-size: 9px; color: var(--neon); text-shadow: 0 0 6px var(--neon); min-width: 28px; text-align: right; }
        input[type=range]#speed-slider { -webkit-appearance: none; appearance: none; width: 70px; height: 3px; background: rgba(0,255,231,0.2); border-radius: 2px; outline: none; cursor: crosshair; }
        input[type=range]#speed-slider::-webkit-slider-thumb { -webkit-appearance: none; width: 12px; height: 12px; border-radius: 50%; background: var(--neon); box-shadow: 0 0 6px var(--neon); cursor: crosshair; }
        .zoom-btn { width: 22px; height: 22px; background: transparent; border: 1px solid var(--border); color: var(--neon); font-size: 14px; line-height: 1; cursor: crosshair; display: flex; align-items: center; justify-content: center; border-radius: 2px; transition: all 0.15s; flex-shrink: 0; }
        .zoom-btn:hover { background: rgba(0,255,231,0.1); }
        #zoom-val { font-size: 9px; color: var(--neon); min-width: 28px; text-align: center; }
        .reboot-btn { border-color: rgba(255,200,0,0.4); color: rgba(255,200,0,0.6); }
        .reboot-btn:hover { border-color: #ffc800; color: #ffc800; }
        .off-btn { border-color: rgba(255,0,60,0.4); color: rgba(255,0,60,0.6); }
        .off-btn:hover { border-color: var(--neon2); color: var(--neon2); }
        .boost-btn { border-color: rgba(255,200,0,0.4); color: rgba(255,200,0,0.6); }
        .boost-btn:hover { border-color: #ffc800; color: #ffc800; }
        .boost-btn.active { background: rgba(255,200,0,0.15); border-color: #ffc800; color: #ffc800; box-shadow: 0 0 16px rgba(255,200,0,0.5); animation: boostpulse 0.3s infinite alternate; }
        @keyframes boostpulse { from{box-shadow:0 0 10px rgba(255,200,0,0.4)} to{box-shadow:0 0 24px rgba(255,200,0,0.8)} }
        .estop-btn { border-color: rgba(255,0,60,0.6); color: rgba(255,0,60,0.8); }
        .estop-btn:hover { background: rgba(255,0,60,0.15); border-color: var(--neon2); color: var(--neon2); }
        .estop-btn.triggered { animation: estoppulse 0.2s 3; }
        @keyframes estoppulse { 0%,100%{box-shadow:0 0 10px rgba(255,0,60,0.4)} 50%{box-shadow:0 0 30px rgba(255,0,60,1)} }
        #dir-display { position: fixed; left: 16px; top: 50%; transform: translateY(-50%); z-index: 30; display: flex; flex-direction: column; align-items: center; gap: 4px; }
        .dir-label { font-family: 'Orbitron', monospace; font-size: 7px; letter-spacing: 3px; color: rgba(0,255,231,0.3); writing-mode: vertical-rl; }
        #dir-arrow { font-size: 20px; color: var(--neon); text-shadow: 0 0 15px var(--neon); transition: all 0.1s; opacity: 0.3; }
        #dir-arrow.active { opacity: 1; }
        #action-btns { position: fixed; bottom: 120px; left: 20px; z-index: 30; display: flex; flex-direction: column; gap: 8px; }
        #status-bar { position: fixed; bottom: 8px; left: 50%; transform: translateX(-50%); z-index: 30; display: flex; gap: 14px; align-items: center; }
        .status-item { font-size: 8px; letter-spacing: 2px; color: rgba(0,255,231,0.4); text-transform: uppercase; }
        .status-item span { color: var(--neon); text-shadow: 0 0 5px var(--neon); }
        #joystick-zone { position: fixed; bottom: 30px; right: 30px; width: 180px; height: 180px; z-index: 10; }
        #joystick-ring { position: fixed; bottom: 20px; right: 20px; width: 200px; height: 200px; border: 1px solid var(--border); border-radius: 50%; z-index: 9; pointer-events: none; box-shadow: 0 0 20px rgba(0,255,231,0.1), inset 0 0 20px rgba(0,255,231,0.05); }
        #joystick-ring::before { content: ''; position: absolute; inset: 8px; border: 1px solid rgba(0,255,231,0.1); border-radius: 50%; }
    </style>
</head>
<body>

    <img id="camera-feed" src="">

    <div class="corner tl"></div>
    <div class="corner tr"></div>
    <div class="corner bl"></div>
    <div class="corner br"></div>

    <div id="crosshair-wrap" class="cross">
        <div class="ch-h"></div>
    </div>

    <div id="move-flash"></div>

    <!-- TOP BAR -->
    <div id="top-bar">
        <div id="top-left">
            <button class="top-btn" onclick="reloadStream()">RELOAD</button>
            <button class="top-btn reboot-btn" onclick="power('reboot')">REBOOT</button>
            <button class="top-btn off-btn" onclick="power('shutdown')">OFF</button>
        </div>
        <div id="top-centre">
            <div class="hud-dot"></div>
            <div id="hud-title">FPV RC-01</div>
            <div class="hud-dot"></div>
        </div>
        <div id="top-right">
            <div class="ctrl-group">
                <span class="ctrl-label">SPD</span>
                <input type="range" id="speed-slider" min="10" max="70" value="60" step="5">
                <span class="ctrl-val" id="speed-val">60%</span>
            </div>
            <div class="ctrl-group">
                <span class="ctrl-label">ZOOM</span>
                <button class="zoom-btn" onclick="adjustZoom(-0.25)">-</button>
                <span id="zoom-val">1.0x</span>
                <button class="zoom-btn" onclick="adjustZoom(0.25)">+</button>
            </div>
            <button id="res-btn" class="top-btn" onclick="cycleResolution()">RES: LOW</button>
            <button id="ch-btn" class="top-btn" onclick="cycleCrosshair()">CH: CROSS</button>
        </div>
    </div>

    <div id="action-btns">
        <button id="boost-btn" class="top-btn boost-btn"
            onmousedown="startBoost()" onmouseup="endBoost()"
            ontouchstart="startBoost()" ontouchend="endBoost()">BOOST</button>
        <button id="estop-btn" class="top-btn estop-btn" onclick="emergencyStop()">STOP</button>
    </div>

    <div id="dir-display">
        <div class="dir-label">VEC</div>
        <div id="dir-arrow">o</div>
    </div>

    <div id="status-bar">
        <div class="status-item">SPD <span id="spd-status">60%</span></div>
        <div class="status-item">CAM <span id="cam-status">OFF</span></div>
        <div class="status-item">CTRL <span id="ctrl-status">IDLE</span></div>
        <div class="status-item">ZOOM <span id="zoom-status">1.0x</span></div>
        <div class="status-item">RES <span id="res-status">LOW</span></div>
    </div>

    <div id="joystick-ring"></div>
    <div id="joystick-zone"></div>

    <script>
        let base_url = "", speed = 0.6, lastDir = 'stop', currentIP = "";
        let zoomLevel = 1.0;
        const MIN_ZOOM = 0.5, MAX_ZOOM = 4.0;
        const dirMap = { up: 'down', down: 'up', left: 'left', right: 'right' };
        const dirArrows = { up: '^', down: 'v', left: '<', right: '>', stop: 'o' };

        const resolutions = ['low', 'med', 'high'];
        const resLabels   = { low: 'LOW', med: 'MED', high: 'HIGH' };
        let resIndex = 0;

        function cycleResolution() {
            resIndex = (resIndex + 1) % resolutions.length;
            const res = resolutions[resIndex];
            document.getElementById('res-btn').textContent = 'RES: ' + resLabels[res];
            document.getElementById('res-status').textContent = resLabels[res];
            if (base_url) {
                fetch(base_url + "/resolution?res=" + res);
                document.getElementById('cam-status').textContent = 'SWITCHING';
                setTimeout(() => { document.getElementById('cam-status').textContent = 'LIVE'; reloadStream(); }, 2000);
            }
        }

        const crosshairStyles = ['cross', 'dot', 'circle', 'target', 'none'];
        const crosshairLabels = { cross: 'CROSS', dot: 'DOT', circle: 'CIRCLE', target: 'TARGET', none: 'OFF' };
        let chIndex = 0;

        function applyCrosshair(style) {
            const el = document.getElementById('crosshair-wrap');
            crosshairStyles.forEach(s => el.classList.remove(s));
            el.classList.add(style);
            document.getElementById('ch-btn').textContent = 'CH: ' + crosshairLabels[style];
            localStorage.setItem('crosshairStyle', style);
        }

        function cycleCrosshair() {
            chIndex = (chIndex + 1) % crosshairStyles.length;
            applyCrosshair(crosshairStyles[chIndex]);
        }

        let keepaliveInterval = null;

        function startKeepalive(dir) {
            stopKeepalive();
            keepaliveInterval = setInterval(() => {
                if (base_url && dir !== 'stop') fetch(base_url + "/move?dir=" + dir + "&speed=" + speed);
            }, 300);
        }

        function stopKeepalive() {
            if (keepaliveInterval) { clearInterval(keepaliveInterval); keepaliveInterval = null; }
        }

        function connect(ip) {
            currentIP = ip;
            base_url = "http://" + ip + ":5000";
            document.getElementById('camera-feed').src = "http://" + ip + ":5000/stream";
            document.getElementById('cam-status').textContent = 'LIVE';
            document.getElementById('ctrl-status').textContent = 'ARMED';
        }

        function reloadStream() {
            if (currentIP) document.getElementById('camera-feed').src = "http://" + currentIP + ":5000/stream?t=" + Date.now();
        }

        function power(action) {
            if (confirm("CONFIRM: " + action.toUpperCase() + "?")) fetch(base_url + "/power?action=" + action);
        }

        document.getElementById('speed-slider').addEventListener('input', function() {
            if (boosting) return;
            speed = this.value / 100;
            const pct = this.value + '%';
            document.getElementById('speed-val').textContent = pct;
            document.getElementById('spd-status').textContent = pct;
        });

        function adjustZoom(delta) {
            zoomLevel = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, +(zoomLevel + delta).toFixed(2)));
            applyZoom();
        }
        function applyZoom() {
            const label = zoomLevel.toFixed(1) + 'x';
            document.getElementById('camera-feed').style.transform = "scale(" + zoomLevel + ")";
            document.getElementById('zoom-val').textContent = label;
            document.getElementById('zoom-status').textContent = label;
        }

        let lastPinchDist = null;
        document.addEventListener('touchmove', (e) => {
            if (e.touches.length === 2) {
                const dx = e.touches[0].clientX - e.touches[1].clientX;
                const dy = e.touches[0].clientY - e.touches[1].clientY;
                const dist = Math.sqrt(dx*dx + dy*dy);
                if (lastPinchDist !== null) adjustZoom((dist - lastPinchDist) * 0.008);
                lastPinchDist = dist;
            }
        }, { passive: true });
        document.addEventListener('touchend', () => { lastPinchDist = null; });
        document.addEventListener('wheel', (e) => { e.preventDefault(); adjustZoom(e.deltaY < 0 ? 0.1 : -0.1); }, { passive: false });

        function emergencyStop() {
            if (base_url) fetch(base_url + "/move?dir=stop");
            stopKeepalive(); endBoost();
            lastDir = 'stop'; heldKeys.clear();
            document.getElementById('estop-btn').classList.add('triggered');
            setTimeout(() => document.getElementById('estop-btn').classList.remove('triggered'), 700);
            document.getElementById('dir-arrow').textContent = 'o';
            document.getElementById('dir-arrow').classList.remove('active');
            document.getElementById('move-flash').classList.remove('active');
            document.getElementById('ctrl-status').textContent = 'STOPPED';
        }

        let boosting = false, boostTimeout = null;
        const BOOST_SPEED = 0.9, BOOST_DURATION = 2500;

        function startBoost() {
            if (!base_url) return;
            boosting = true; speed = BOOST_SPEED;
            document.getElementById('boost-btn').classList.add('active');
            document.getElementById('spd-status').textContent = 'BOOST';
            document.getElementById('speed-val').textContent = 'BOOST';
            if (lastDir !== 'stop') sendMove(lastDir);
            clearTimeout(boostTimeout);
            boostTimeout = setTimeout(endBoost, BOOST_DURATION);
        }

        function endBoost() {
            boosting = false; clearTimeout(boostTimeout);
            const sliderVal = document.getElementById('speed-slider').value;
            speed = sliderVal / 100;
            document.getElementById('boost-btn').classList.remove('active');
            document.getElementById('speed-val').textContent = sliderVal + '%';
            document.getElementById('spd-status').textContent = sliderVal + '%';
            if (lastDir !== 'stop') sendMove(lastDir);
        }

        function sendMove(dir) {
            if (!base_url) return;
            fetch(base_url + "/move?dir=" + dir + "&speed=" + speed);
            const arrow = document.getElementById('dir-arrow');
            const ctrl = document.getElementById('ctrl-status');
            if (dir === 'stop') {
                stopKeepalive();
                arrow.textContent = 'o'; arrow.classList.remove('active');
                document.getElementById('move-flash').classList.remove('active');
                ctrl.textContent = 'IDLE';
            } else {
                startKeepalive(dir);
                arrow.textContent = dirArrows[dir] || 'o'; arrow.classList.add('active');
                document.getElementById('move-flash').classList.add('active');
                ctrl.textContent = dir.toUpperCase();
            }
            lastDir = dir;
        }

        var joystick = nipplejs.create({
            zone: document.getElementById('joystick-zone'),
            mode: 'static', position: { left: '50%', top: '50%' },
            color: 'rgba(0,255,231,0.8)', size: 140, fadeTime: 100, threshold: 0.3
        });
        joystick.on('move', (evt, data) => {
            if (data.direction && base_url && data.force > 0.3) {
                let dir = dirMap[data.direction.angle] || data.direction.angle;
                if (dir !== lastDir) sendMove(dir);
            }
        });
        joystick.on('end', () => { sendMove('stop'); });

        const keys = { w: 'down', s: 'up', a: 'left', d: 'right' };
        const heldKeys = new Set();

        document.addEventListener('keydown', (e) => {
            if (e.repeat) return;
            if (e.key === 'Escape') { emergencyStop(); return; }
            if (e.code === 'Space' && !boosting) { e.preventDefault(); startBoost(); return; }
            if (e.key === '=' || e.key === '+') { adjustZoom(0.25); return; }
            if (e.key === '-') { adjustZoom(-0.25); return; }
            if (e.key === '0') { zoomLevel = 1.0; applyZoom(); return; }
            if (e.key === 'r' || e.key === 'R') { cycleResolution(); return; }
            if (e.key === 'c' || e.key === 'C') { cycleCrosshair(); return; }
            const dir = keys[e.key.toLowerCase()];
            if (dir && !heldKeys.has(dir)) { heldKeys.add(dir); sendMove(dir); }
        });

        document.addEventListener('keyup', (e) => {
            if (e.code === 'Space') { endBoost(); return; }
            const dir = keys[e.key.toLowerCase()];
            if (dir) {
                heldKeys.delete(dir);
                if (heldKeys.size === 0) sendMove('stop');
                else sendMove(keys[Array.from(heldKeys)[0]]);
            }
        });

        window.onload = () => {
            const saved = localStorage.getItem('crosshairStyle');
            if (saved && crosshairStyles.includes(saved)) {
                chIndex = crosshairStyles.indexOf(saved);
                applyCrosshair(saved);
            }
            const ip = window.location.hostname;
            if (ip) connect(ip);
        };
    </script>
</body>
</html>
HTMLEOF

# Step 7 - Set up systemd service
echo "[7/8] Setting up auto-start service..."
sudo tee /etc/systemd/system/robotcar.service << 'SVCEOF'
[Unit]
Description=Robot Car Controller
After=network.target

[Service]
User=pi
WorkingDirectory=/home/pi/robot_car
Environment=GPIOZERO_PIN_FACTORY=rpigpio
ExecStartPre=/bin/sleep 10
ExecStart=/usr/bin/python3 /home/pi/robot_car/app.py
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=3

[Install]
WantedBy=multi-user.target
SVCEOF

sudo systemctl daemon-reload
sudo systemctl enable robotcar

echo ""
echo "======================================"
echo "  SETUP COMPLETE!"
echo "  Rebooting in 5 seconds..."
echo "  After reboot open:"
echo "  http://192.168.1.206:5000"
echo "======================================"
sleep 5
sudo reboot
