#!/bin/bash
#
# Helios-Victron Installation Script (Modbus TCP)
# ==================================================
#
# Installs the Huawei SUN2000 Modbus TCP daemon on Victron Cerbo GX.
# Runs as an independent service, registers its own D-Bus service.
#
# Usage (run directly on Cerbo GX):
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
#   bash /tmp/install.sh <dongle-ip>
#
# Example:
#   bash /tmp/install.sh 172.20.0.186
#

set -e

REPO_URL="https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master"
DATA_DIR="/data/helios-victron"
SERVICE_DIR="/service/helios-huawei-tcp"
RC_LOCAL="/data/rc.local"
RC_MARKER="# helios-victron TCP daemon"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}ℹ ${NC}$1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_header()  { echo ""; echo "========================================="; echo "$1"; echo "========================================="; echo ""; }

[ "$EUID" -ne 0 ] && { print_error "Please run as root (ssh root@<cerbo-ip>)"; exit 1; }

print_header "☀️  Helios-Victron TCP Installation"

# ---------------------------------------------------------------------------
# Step 1: Get dongle IP
# ---------------------------------------------------------------------------
if [ -z "$1" ]; then
    print_warning "No dongle IP specified."
    read -p "Enter Huawei SDongle IP address: " DONGLE_IP
    [ -z "$DONGLE_IP" ] && { print_error "No IP specified. Exiting."; exit 1; }
else
    DONGLE_IP="$1"
fi

print_header "Step 1: Verify Dongle Connectivity"

python3 - "$DONGLE_IP" << 'PYEOF'
import sys, time
from pymodbus.client.sync import ModbusTcpClient
ip = sys.argv[1]
c = ModbusTcpClient(ip, port=502, timeout=5)
if not c.connect():
    print(f"FAILED to connect to {ip}:502")
    sys.exit(1)
time.sleep(1)
r = c.read_holding_registers(30070, 1, unit=1)
if hasattr(r, 'registers'):
    print(f"OK - Model ID: {r.registers[0]}")
else:
    print(f"Connected but no Modbus response: {r}")
    sys.exit(1)
c.close()
PYEOF

if [ $? -ne 0 ]; then
    print_error "Could not reach Huawei inverter via TCP at $DONGLE_IP:502"
    echo ""
    echo "Check:"
    echo "  1. Dongle IP is correct and reachable"
    echo "  2. Modbus TCP is enabled in the SUN2000 App (Installer login →"
    echo "     Communication → Modbus TCP)"
    exit 1
fi
print_success "Dongle reachable, inverter responding"

# ---------------------------------------------------------------------------
# Step 2: Get daemon file
# ---------------------------------------------------------------------------
print_header "Step 2: Get Daemon"

if [ -f "helios-huawei-tcp.py" ]; then
    print_info "Using local helios-huawei-tcp.py"
    DAEMON_PY="helios-huawei-tcp.py"
else
    print_info "Downloading from GitHub..."
    wget -q -O /tmp/helios-huawei-tcp.py "$REPO_URL/helios-huawei-tcp.py" || {
        print_error "Download failed."; exit 1
    }
    DAEMON_PY="/tmp/helios-huawei-tcp.py"
    print_success "Downloaded"
fi

# ---------------------------------------------------------------------------
# Step 3: Install to /data/ with configured IP
# ---------------------------------------------------------------------------
print_header "Step 3: Install Daemon"

mkdir -p "$DATA_DIR"
cp "$DAEMON_PY" "$DATA_DIR/helios-huawei-tcp.py"
sed -i "s/^DONGLE_IP        = '.*'/DONGLE_IP        = '$DONGLE_IP'/" \
    "$DATA_DIR/helios-huawei-tcp.py"
chmod 755 "$DATA_DIR/helios-huawei-tcp.py"
print_success "Installed to $DATA_DIR/ (dongle IP: $DONGLE_IP)"

# ---------------------------------------------------------------------------
# Step 4: Disable legacy RTU plugin if present (avoid duplicate D-Bus service)
# ---------------------------------------------------------------------------
print_header "Step 4: Check for Legacy RTU Plugin"

MODBUS_DIR="/opt/victronenergy/dbus-modbus-client"
if [ -f "$MODBUS_DIR/huawei.py" ] || grep -q "^import huawei$" "$MODBUS_DIR/dbus-modbus-client.py" 2>/dev/null; then
    print_warning "Legacy RTU huawei.py plugin detected — removing to avoid duplicate D-Bus service"
    mount -o remount,rw /
    sed -i '/^import huawei$/d' "$MODBUS_DIR/dbus-modbus-client.py" 2>/dev/null || true
    rm -f "$MODBUS_DIR/huawei.py"
    rm -rf "$MODBUS_DIR/__pycache__/" 2>/dev/null || true
    mount -o remount,ro /
    print_success "Legacy RTU plugin removed"

    # Remove old rc.local entry if present
    sed -i "/# helios-victron$/,/^mount -o remount,ro \//d" "$RC_LOCAL" 2>/dev/null || true

    print_info "Restarting dbus-modbus-client to drop RTU Huawei..."
    for svc in /service/dbus-modbus-client.serial.*; do
        [ -e "$svc" ] && svc -t "$svc" 2>/dev/null || true
    done
else
    print_info "No legacy RTU plugin found"
fi

# ---------------------------------------------------------------------------
# Step 5: Install runit service
# ---------------------------------------------------------------------------
print_header "Step 5: Install Service"

mkdir -p "$SERVICE_DIR/log"
cat > "$SERVICE_DIR/run" << 'RUNEOF'
#!/bin/sh
exec /usr/bin/python3 -u /data/helios-victron/helios-huawei-tcp.py 2>&1
RUNEOF
cat > "$SERVICE_DIR/log/run" << 'LOGEOF'
#!/bin/sh
exec multilog t s25000 n4 /var/log/helios-huawei-tcp
LOGEOF
chmod 755 "$SERVICE_DIR/run"
chmod 755 "$SERVICE_DIR/log/run"

# Persist service scripts to /data/
mkdir -p "$DATA_DIR/service/helios-huawei-tcp/log"
cp "$SERVICE_DIR/run" "$DATA_DIR/service/helios-huawei-tcp/"
cp "$SERVICE_DIR/log/run" "$DATA_DIR/service/helios-huawei-tcp/log/"
chmod 755 "$DATA_DIR/service/helios-huawei-tcp/run"
chmod 755 "$DATA_DIR/service/helios-huawei-tcp/log/run"

print_success "runit service installed: $SERVICE_DIR"

# ---------------------------------------------------------------------------
# Step 6: Persist via rc.local
# ---------------------------------------------------------------------------
print_header "Step 6: Persist via rc.local"

if ! grep -q "$RC_MARKER" "$RC_LOCAL" 2>/dev/null; then
    cat >> "$RC_LOCAL" << EOF

$RC_MARKER
if [ ! -f $SERVICE_DIR/run ]; then
    mkdir -p $SERVICE_DIR/log
    cp $DATA_DIR/service/helios-huawei-tcp/run $SERVICE_DIR/
    cp $DATA_DIR/service/helios-huawei-tcp/log/run $SERVICE_DIR/log/
    chmod 755 $SERVICE_DIR/run
    chmod 755 $SERVICE_DIR/log/run
fi
EOF
    chmod +x "$RC_LOCAL"
    print_success "rc.local updated (service auto-restored after firmware updates)"
else
    print_info "rc.local already configured"
fi

# ---------------------------------------------------------------------------
# Step 7: Start service
# ---------------------------------------------------------------------------
print_header "Step 7: Start Service"

touch "$SERVICE_DIR/down"
sleep 1
rm -f "$SERVICE_DIR/down"
sleep 3

STATUS=$(svstat "$SERVICE_DIR" 2>/dev/null || echo "unknown")
echo "  $STATUS"
echo "$STATUS" | grep -q "up" && print_success "Service running" || print_warning "Service starting..."

# ---------------------------------------------------------------------------
# Step 8: Verify
# ---------------------------------------------------------------------------
print_header "Step 8: Verification"

print_info "Waiting for first poll cycle (up to 40s)..."
sleep 15
DETECTED=$(dbus -y 2>/dev/null | grep -c "huawei_sun2000" || echo "0")
if [ "$DETECTED" -gt 0 ]; then
    print_success "D-Bus service active: com.victronenergy.pvinverter.huawei_sun2000"
    CONNECTED=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Connected GetValue 2>/dev/null || echo "N/A")
    echo "  Connected: $CONNECTED"
else
    print_warning "D-Bus service not detected yet — check logs:"
    echo "  tail -f /var/log/helios-huawei-tcp/current | tai64nlocal"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
print_header "✅ Installation Complete!"
echo "  Daemon:     $DATA_DIR/helios-huawei-tcp.py"
echo "  Dongle IP:  $DONGLE_IP"
echo "  Service:    $SERVICE_DIR"
echo "  Persistent: $RC_LOCAL"
echo ""
echo "Monitor:"
echo "  tail -f /var/log/helios-huawei-tcp/current | tai64nlocal"
echo "  dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue"
echo ""
echo "⚠ RS485 (RTU) and the SDongle cannot be used simultaneously."
echo "  If a wallbox or other device needs RS485, connect it directly to"
echo "  the Cerbo — do not share the bus with the Huawei COM port."
echo ""
print_success "Done! ☀️"
