#!/bin/bash
#
# Helios-Victron Installation Script
# ===================================
#
# Installs Huawei SUN2000 Modbus RTU integration on Victron Cerbo GX.
# Compatible with Venus OS 3.70+ (read-only filesystem).
#
# Usage (run directly on Cerbo GX):
#   wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
#   bash /tmp/install.sh [ttyUSBX]
#
# Or if you have the repo cloned locally:
#   ./install.sh [ttyUSBX]
#

set -e

REPO_URL="https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master"
DATA_DIR="/data/helios-victron"
TARGET_DIR="/opt/victronenergy/dbus-modbus-client"
RC_LOCAL="/data/rc.local"
RC_MARKER="# helios-victron"

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

print_header "☀️  Helios-Victron Installation"

# ---------------------------------------------------------------------------
# Step 1: Get huawei.py
# ---------------------------------------------------------------------------
print_header "Step 1: Get Plugin"

if [ -f "huawei.py" ]; then
    print_info "Using local huawei.py"
    HUAWEI_PY="huawei.py"
else
    print_info "Downloading huawei.py from GitHub..."
    wget -q -O /tmp/huawei.py "$REPO_URL/huawei.py" || {
        print_error "Download failed. Check internet connection."
        exit 1
    }
    HUAWEI_PY="/tmp/huawei.py"
    print_success "Downloaded huawei.py"
fi

# ---------------------------------------------------------------------------
# Step 2: Identify USB device
# ---------------------------------------------------------------------------
print_header "Step 2: Identify USB Device"

echo "Available USB serial devices:"
ls -l /dev/ttyUSB* 2>/dev/null || {
    print_error "No USB serial devices found!"
    exit 1
}
echo ""

if [ -z "$1" ]; then
    print_warning "No device specified."
    echo ""
    for dev in /dev/ttyUSB*; do
        devname=$(basename "$dev")
        echo "  $devname:"
        services=$(ls /service/*${devname}* 2>/dev/null | head -n 5)
        [ -n "$services" ] && echo "$services" | sed 's/^/    /' || echo "    (no services running)"
        echo ""
    done
    read -p "Enter device name (e.g. ttyUSB1): " DEVICE
    [ -z "$DEVICE" ] && { print_error "No device specified."; exit 1; }
else
    DEVICE="$1"
fi

[ ! -e "/dev/$DEVICE" ] && { print_error "Device /dev/$DEVICE does not exist!"; exit 1; }
print_success "Using device: $DEVICE"

# ---------------------------------------------------------------------------
# Step 3: Install to /data/ and create symlink
# ---------------------------------------------------------------------------
print_header "Step 3: Install Plugin"

mkdir -p "$DATA_DIR"
cp "$HUAWEI_PY" "$DATA_DIR/huawei.py"
chmod 644 "$DATA_DIR/huawei.py"
print_success "huawei.py installed to $DATA_DIR/"

print_info "Patching filesystem (remount rw)..."
mount -o remount,rw /

# Symlink
[ -f "$TARGET_DIR/huawei.py" ] && [ ! -L "$TARGET_DIR/huawei.py" ] && \
    cp "$TARGET_DIR/huawei.py" "$TARGET_DIR/huawei.py.backup.$(date +%Y%m%d_%H%M%S)"
ln -sf "$DATA_DIR/huawei.py" "$TARGET_DIR/huawei.py"
print_success "Symlink: $TARGET_DIR/huawei.py → $DATA_DIR/huawei.py"

# Patch dbus-modbus-client.py to import huawei
if ! grep -q "import huawei" "$TARGET_DIR/dbus-modbus-client.py"; then
    sed -i 's/^import victron_em$/import victron_em\nimport huawei/' \
        "$TARGET_DIR/dbus-modbus-client.py"
    print_success "Added 'import huawei' to dbus-modbus-client.py"
else
    print_info "dbus-modbus-client.py already imports huawei"
fi

# Clear pycache
rm -rf "$TARGET_DIR/__pycache__/" 2>/dev/null || true

mount -o remount,ro /
print_success "Filesystem restored to read-only"

# ---------------------------------------------------------------------------
# Step 4: Persist via rc.local (survives firmware updates)
# ---------------------------------------------------------------------------
print_header "Step 4: Persist via rc.local"

if ! grep -q "$RC_MARKER" "$RC_LOCAL" 2>/dev/null; then
    cat >> "$RC_LOCAL" << EOF

$RC_MARKER
mount -o remount,rw /
ln -sf $DATA_DIR/huawei.py $TARGET_DIR/huawei.py
if ! grep -q "import huawei" $TARGET_DIR/dbus-modbus-client.py; then
    sed -i 's/^import victron_em\$/import victron_em\\nimport huawei/' $TARGET_DIR/dbus-modbus-client.py
fi
rm -rf $TARGET_DIR/__pycache__/ 2>/dev/null || true
mount -o remount,ro /
EOF
    chmod +x "$RC_LOCAL"
    print_success "rc.local updated (auto-restore after firmware updates)"
else
    # Update existing entry
    print_info "Updating existing rc.local entry..."
    # Remove old entry and rewrite
    sed -i "/$RC_MARKER/,/^mount -o remount,ro \//d" "$RC_LOCAL" 2>/dev/null || true
    cat >> "$RC_LOCAL" << EOF

$RC_MARKER
mount -o remount,rw /
ln -sf $DATA_DIR/huawei.py $TARGET_DIR/huawei.py
if ! grep -q "import huawei" $TARGET_DIR/dbus-modbus-client.py; then
    sed -i 's/^import victron_em\$/import victron_em\\nimport huawei/' $TARGET_DIR/dbus-modbus-client.py
fi
rm -rf $TARGET_DIR/__pycache__/ 2>/dev/null || true
mount -o remount,ro /
EOF
    print_success "rc.local updated"
fi

# ---------------------------------------------------------------------------
# Step 5: Configure Modbus
# ---------------------------------------------------------------------------
print_header "Step 5: Configure Modbus"

dbus -y com.victronenergy.settings \
    /Settings/ModbusClient/${DEVICE}/AutoScan SetValue 1 >/dev/null 2>&1
dbus -y com.victronenergy.settings \
    /Settings/ModbusClient/${DEVICE}/Devices SetValue "" >/dev/null 2>&1
print_success "Auto-scan enabled on $DEVICE"

# ---------------------------------------------------------------------------
# Step 6: Restart services
# ---------------------------------------------------------------------------
print_header "Step 6: Restart Services"

svc -t /service/serial-starter
print_success "Serial-starter restarted"

# ---------------------------------------------------------------------------
# Step 7: Wait for detection
# ---------------------------------------------------------------------------
print_header "Step 7: Waiting for Device Detection"

print_info "Waiting up to 60 seconds..."
echo -n "Progress: "
DETECTED=0
for i in $(seq 1 60); do
    echo -n "."
    sleep 1
    if dbus -y 2>/dev/null | grep -q "huawei_sun2000"; then
        echo ""; DETECTED=1; break
    fi
done
echo ""

# ---------------------------------------------------------------------------
# Step 8: Verify
# ---------------------------------------------------------------------------
print_header "Step 8: Verification"

if [ "$DETECTED" -eq 1 ] || dbus -y 2>/dev/null | grep -q "huawei_sun2000"; then
    print_success "Device found: com.victronenergy.pvinverter.huawei_sun2000"
    echo ""
    POWER=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Ac/Power GetValue 2>/dev/null || echo "N/A")
    echo "  AC Power:    $POWER W"
    YIELD=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Yield/Power GetValue 2>/dev/null || echo "N/A")
    echo "  Lifetime:    $YIELD kWh"
    STATUS=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /StatusCode GetValue 2>/dev/null || echo "N/A")
    printf "  Status:      %s" "$STATUS"
    case "$STATUS" in
        512)   echo " (On-grid running)" ;;
        40960) echo " (Standby: no irradiation)" ;;
        *)     echo "" ;;
    esac
    TEMP=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Temperature GetValue 2>/dev/null || echo "N/A")
    echo "  Temperature: $TEMP °C"
else
    print_error "Huawei SUN2000 not detected after 60 seconds!"
    echo ""
    echo "Common fixes:"
    echo "  1. SDongle plugged in? → Unplug it, then power-cycle the inverter."
    echo "  2. After Huawei firmware update? → Power-cycle (AC off, 2min, back on)."
    echo "  3. Wrong wiring? → Pin5=GND, Pin7=A(+), Pin9=B(-)"
    echo ""
    echo "Logs: tail -50 /var/log/dbus-modbus-client.${DEVICE}/current | tai64nlocal"
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
print_header "✅ Installation Complete!"
echo "  Plugin:     $DATA_DIR/huawei.py"
echo "  Symlink:    $TARGET_DIR/huawei.py"
echo "  Import:     patched into dbus-modbus-client.py"
echo "  Persistent: $RC_LOCAL (auto-restore after firmware updates)"
echo ""
echo "To update to latest version:"
echo "  wget -O /tmp/install.sh $REPO_URL/install.sh && bash /tmp/install.sh $DEVICE"
echo ""
echo "⚠ SDongle and RS485 cannot be used simultaneously."
echo "⚠ After Huawei firmware update: power-cycle the inverter."
echo ""
print_success "Done! ☀️"

