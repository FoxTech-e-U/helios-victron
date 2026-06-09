#!/bin/bash
#
# Helios-Victron Installation Script
# ===================================
#
# Installs Huawei SUN2000 Modbus RTU integration on Victron Cerbo GX.
# Supports shared RS485 buses with multiple devices (e.g. ABB Terra wallbox).
#
# Usage:
#   ./install.sh [ttyUSBX]
#
# Example:
#   ./install.sh ttyUSB1
#
# If no device is specified the script will help you identify it.
#

set -e

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

# ---------------------------------------------------------------------------
# Root check
# ---------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (ssh root@<cerbo-ip>)"
    exit 1
fi

print_header "☀️  Helios-Victron Installation"

# ---------------------------------------------------------------------------
# Check huawei.py is present
# ---------------------------------------------------------------------------
if [ ! -f "huawei.py" ]; then
    print_error "huawei.py not found in current directory!"
    echo "Please run this script from inside the helios-victron directory."
    exit 1
fi

# ---------------------------------------------------------------------------
# Step 1: Identify USB device
# ---------------------------------------------------------------------------
print_header "Step 1: Identify USB Device"

echo "Available USB serial devices:"
ls -l /dev/ttyUSB* 2>/dev/null || {
    print_error "No USB serial devices found!"
    echo "Check that the RS485-USB adapter is connected."
    exit 1
}
echo ""

if [ -z "$1" ]; then
    print_warning "No device specified. Which ttyUSB is your Huawei inverter?"
    echo ""
    echo "Current USB devices and their active services:"
    for dev in /dev/ttyUSB*; do
        devname=$(basename "$dev")
        echo "  $devname:"
        services=$(ls /service/*${devname}* 2>/dev/null | head -n 5)
        if [ -n "$services" ]; then
            echo "$services" | sed 's/^/    /'
        else
            echo "    (no services running)"
        fi
        echo ""
    done
    echo "Tip: Unplug/replug the RS485-USB adapter to identify the device."
    echo ""
    read -p "Enter device name (e.g. ttyUSB1): " DEVICE
    [ -z "$DEVICE" ] && { print_error "No device specified. Exiting."; exit 1; }
else
    DEVICE="$1"
fi

[ ! -e "/dev/$DEVICE" ] && { print_error "Device /dev/$DEVICE does not exist!"; exit 1; }
print_success "Using device: $DEVICE"

# ---------------------------------------------------------------------------
# Step 2: Install huawei.py
# ---------------------------------------------------------------------------
print_header "Step 2: Backup & Install"

TARGET_DIR="/opt/victronenergy/dbus-modbus-client"
TARGET_FILE="$TARGET_DIR/huawei.py"

if [ -f "$TARGET_FILE" ]; then
    BACKUP="$TARGET_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backing up existing file to: $BACKUP"
    cp "$TARGET_FILE" "$BACKUP"
fi

cp huawei.py "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
print_success "huawei.py installed to $TARGET_DIR/"

# ---------------------------------------------------------------------------
# Step 3: Discover all Modbus devices on the bus
# ---------------------------------------------------------------------------
print_header "Step 3: Scan Bus for Modbus Devices"

print_info "Stopping all services on $DEVICE to free the port..."
for svc in /service/*${DEVICE}*; do
    [ -e "$svc" ] && { svc -d "$svc" 2>/dev/null || true; }
done
# Also kill any lingering process holding the port
fuser -k "/dev/$DEVICE" 2>/dev/null || true
sleep 2

print_info "Scanning Modbus addresses 1-10 on $DEVICE @ 9600 baud..."
echo "   (This takes ~30 seconds)"

FOUND_UNITS=""

python3 - "/dev/$DEVICE" << 'PYEOF'
import sys, time
from pymodbus.client.sync import ModbusSerialClient

port = sys.argv[1]
client = ModbusSerialClient(
    method='rtu', port=port, baudrate=9600,
    bytesize=8, parity='N', stopbits=1, timeout=2
)
client.connect()
time.sleep(1)

found = []
for addr in range(1, 11):
    # Try a generic holding register read that most devices respond to
    r = client.read_holding_registers(0, 1, unit=addr)
    if hasattr(r, 'registers'):
        print(f"FOUND:{addr}")
        found.append(addr)
    else:
        # Try alternative base register (Huawei starts at 30000)
        r2 = client.read_holding_registers(30070, 1, unit=addr)
        if hasattr(r2, 'registers'):
            print(f"FOUND:{addr}")
            found.append(addr)
    time.sleep(0.3)

client.close()
if not found:
    print("NONE")
PYEOF

# Parse found units from python output
FOUND_UNITS=$(python3 - "/dev/$DEVICE" 2>/dev/null << 'PYEOF'
import sys, time
from pymodbus.client.sync import ModbusSerialClient

port = sys.argv[1]
client = ModbusSerialClient(
    method='rtu', port=port, baudrate=9600,
    bytesize=8, parity='N', stopbits=1, timeout=2
)
client.connect()
time.sleep(1)

found = []
for addr in range(1, 11):
    r = client.read_holding_registers(30070, 1, unit=addr)
    if hasattr(r, 'registers'):
        found.append(str(addr))
    else:
        r2 = client.read_holding_registers(0x4006, 1, unit=addr)
        if hasattr(r2, 'registers'):
            found.append(str(addr))
    time.sleep(0.3)

client.close()
print(','.join(found))
PYEOF
)

if [ -z "$FOUND_UNITS" ]; then
    print_warning "No devices found by scan. Defaulting to address 1 (Huawei)."
    print_warning "If your inverter does not respond, check:"
    print_warning "  1. Wiring: Pin5=GND, Pin7=A(+), Pin9=B(-)"
    print_warning "  2. Inverter RS485 settings: Slave mode, 9600 baud, address 1"
    print_warning "  3. After a Huawei firmware update: power-cycle the inverter"
    print_warning "     (DC off + AC off, wait 2 minutes, then power back on)"
    FOUND_UNITS="1"
else
    print_success "Found device(s) at address(es): $FOUND_UNITS"
fi

# ---------------------------------------------------------------------------
# Step 4: Configure Modbus device string
# ---------------------------------------------------------------------------
print_header "Step 4: Configure Modbus Settings"

# Build device string: one entry per found address
DEVICE_STRING=""
IFS=',' read -ra UNITS <<< "$FOUND_UNITS"
for unit in "${UNITS[@]}"; do
    [ -n "$DEVICE_STRING" ] && DEVICE_STRING="${DEVICE_STRING},"
    DEVICE_STRING="${DEVICE_STRING}rtu:${DEVICE}:9600:${unit}"
done

# Always ensure address 1 (Huawei) is included
if ! echo "$DEVICE_STRING" | grep -q ":9600:1"; then
    DEVICE_STRING="rtu:${DEVICE}:9600:1,${DEVICE_STRING}"
fi

print_info "Setting device configuration: $DEVICE_STRING"
dbus -y com.victronenergy.settings \
    /Settings/ModbusClient/${DEVICE}/Devices \
    SetValue "$DEVICE_STRING" >/dev/null 2>&1
print_success "Device configuration set"

print_info "Enabling auto-scan..."
dbus -y com.victronenergy.settings \
    /Settings/ModbusClient/${DEVICE}/AutoScan \
    SetValue 1 >/dev/null 2>&1
print_success "Auto-scan enabled"

# ---------------------------------------------------------------------------
# Step 5: Clear Python cache
# ---------------------------------------------------------------------------
print_header "Step 5: Clear Python Cache"

rm -rf ${TARGET_DIR}/__pycache__/huawei* 2>/dev/null || true
rm -rf ${TARGET_DIR}/__pycache__/abb_terra* 2>/dev/null || true
print_success "Python cache cleared"

# ---------------------------------------------------------------------------
# Step 6: Restart services
# ---------------------------------------------------------------------------
print_header "Step 6: Restart Services"

print_info "Stopping all services on $DEVICE..."
for svc in /service/*${DEVICE}*; do
    if [ -e "$svc" ]; then
        svc -d "$svc" 2>/dev/null || true
        print_success "Stopped $(basename $svc)"
    fi
done

# Kill any process still holding the port
fuser -k "/dev/$DEVICE" 2>/dev/null || true
sleep 1

print_info "Restarting serial-starter..."
svc -u /service/serial-starter
svc -t /service/serial-starter
print_success "Serial-starter restarted"

# ---------------------------------------------------------------------------
# Step 7: Wait for device detection
# ---------------------------------------------------------------------------
print_header "Step 7: Waiting for Device Detection"

print_info "Waiting up to 60 seconds for Huawei to appear on D-Bus..."
echo -n "Progress: "
DETECTED=0
for i in $(seq 1 60); do
    echo -n "."
    sleep 1
    if dbus -y 2>/dev/null | grep -q "huawei_sun2000"; then
        echo ""
        DETECTED=1
        break
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
    print_info "Current values:"

    POWER=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Ac/Power GetValue 2>/dev/null || echo "N/A")
    echo "  AC Power:       $POWER W"

    YIELD=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Yield/Power GetValue 2>/dev/null || echo "N/A")
    echo "  Lifetime total: $YIELD kWh"

    DAILY=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Ac/Energy/Forward GetValue 2>/dev/null || echo "N/A")
    echo "  Daily yield:    $DAILY kWh"

    STATUS=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /StatusCode GetValue 2>/dev/null || echo "N/A")
    printf "  Status code:    %s" "$STATUS"
    case "$STATUS" in
        512)  echo " (0x0200 = On-grid running)" ;;
        256)  echo " (0x0100 = Starting)" ;;
        768)  echo " (0x0300 = Fault shutdown)" ;;
        40960) echo " (0xA000 = Standby: no irradiation)" ;;
        *)    echo "" ;;
    esac

    TEMP=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Temperature GetValue 2>/dev/null || echo "N/A")
    echo "  Temperature:    $TEMP °C"

else
    print_error "Huawei SUN2000 not detected on D-Bus after 60 seconds!"
    echo ""
    print_warning "Common causes and fixes:"
    echo ""
    echo "  1. After a Huawei firmware update, the RS485 stack can hang."
    echo "     → Power-cycle the inverter: turn off AC breaker, wait for DC"
    echo "       capacitors to discharge (~2 min), then power back on."
    echo ""
    echo "  2. Wrong wiring (most common physical issue):"
    echo "     → Check: Pin5=GND, Pin7=A(+), Pin9=B(-) at inverter COM port"
    echo "     → Try swapping A and B if no response"
    echo ""
    echo "  3. Inverter RS485 settings reset by firmware update:"
    echo "     → Connect via SUN2000 app to inverter hotspot"
    echo "     → Settings → Communication → RS485_1"
    echo "     → Mode=Slave, Baud=9600, Parity=None, Address=1"
    echo ""
    echo "  4. Model ID not in models dict:"
    echo "     → Run the scan below to find your Model ID"
    echo "     → Add it to huawei.py and re-run install.sh"
    echo ""
    echo "  Diagnostics:"
    echo "    tail -50 /var/log/dbus-modbus-client.${DEVICE}/current | tai64nlocal"
    echo ""
    echo "  Find Model ID manually:"
    echo "    python3 -c \""
    echo "    from pymodbus.client.sync import ModbusSerialClient"
    echo "    c = ModbusSerialClient(method='rtu', port='/dev/$DEVICE',"
    echo "        baudrate=9600, bytesize=8, parity='N', stopbits=1, timeout=3)"
    echo "    c.connect()"
    echo "    r = c.read_holding_registers(30070, 1, unit=1)"
    echo "    print('Model ID:', r.registers[0] if hasattr(r,'registers') else 'no response')"
    echo "    c.close()\""
    exit 1
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
print_header "✅ Installation Complete!"

echo "The Huawei SUN2000 is now integrated into your Victron system."
echo ""
echo "  D-Bus service:  com.victronenergy.pvinverter.huawei_sun2000"
echo "  Device:         /dev/$DEVICE"
echo "  Protocol:       Modbus RTU, 9600 baud"
echo "  Modbus config:  $DEVICE_STRING"
echo ""
echo "Monitor live data:"
echo "  dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue"
echo ""
echo "Watch logs:"
echo "  tail -f /var/log/dbus-modbus-client.${DEVICE}/current | tai64nlocal"
echo ""
echo "⚠ After any Huawei firmware update:"
echo "  Power-cycle the inverter (DC + AC off, wait 2 min) to restore RS485."
echo ""
print_success "Done! ☀️"
