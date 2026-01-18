#!/bin/bash
#
# Helios-Victron Installation Script
# ===================================
# 
# Installs Huawei SUN2000 Modbus RTU integration on Victron Cerbo GX
#
# Usage:
#   ./install.sh [ttyUSBX]
#
# Example:
#   ./install.sh ttyUSB1
#
# If no device specified, script will help you identify it.
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_info() {
    echo -e "${BLUE}ℹ ${NC}$1"
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_header() {
    echo ""
    echo "========================================="
    echo "$1"
    echo "========================================="
    echo ""
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use: ssh root@cerbo-ip)"
    exit 1
fi

print_header "☀️  Helios-Victron Installation"

# Check if huawei.py exists in current directory
if [ ! -f "huawei.py" ]; then
    print_error "huawei.py not found in current directory!"
    echo ""
    echo "Please make sure you're in the helios-victron directory:"
    echo "  cd /path/to/helios-victron"
    echo "  ./install.sh"
    exit 1
fi

# Step 1: Identify USB device
print_header "Step 1: Identify USB Device"

echo "Available USB serial devices:"
ls -l /dev/ttyUSB* 2>/dev/null || {
    print_error "No USB serial devices found!"
    echo ""
    echo "Please check:"
    echo "  1. RS485-USB adapter is plugged in"
    echo "  2. USB cable is properly connected"
    exit 1
}

echo ""

if [ -z "$1" ]; then
    # No device specified - help user identify
    print_warning "No device specified. Which ttyUSB is your Huawei inverter?"
    echo ""
    echo "Current USB devices and their services:"
    for dev in /dev/ttyUSB*; do
        devname=$(basename "$dev")
        echo "  $devname:"
        
        # Check if service exists for this device
        services=$(ls /service/*${devname}* 2>/dev/null | head -n 3)
        if [ -n "$services" ]; then
            echo "$services" | sed 's/^/    /'
        else
            echo "    (no services running)"
        fi
        echo ""
    done
    
    echo "Hint: To identify your device, try unplugging and re-plugging"
    echo "      the RS485-USB adapter and check which device disappears."
    echo ""
    read -p "Enter device name (e.g., ttyUSB1): " DEVICE
    
    if [ -z "$DEVICE" ]; then
        print_error "No device specified. Exiting."
        exit 1
    fi
else
    DEVICE="$1"
fi

# Validate device
if [ ! -e "/dev/$DEVICE" ]; then
    print_error "Device /dev/$DEVICE does not exist!"
    exit 1
fi

print_success "Using device: $DEVICE"

# Step 2: Backup existing file if present
print_header "Step 2: Backup & Install"

TARGET_DIR="/opt/victronenergy/dbus-modbus-client"
TARGET_FILE="$TARGET_DIR/huawei.py"

if [ -f "$TARGET_FILE" ]; then
    BACKUP_FILE="$TARGET_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    print_info "Backing up existing file to: $BACKUP_FILE"
    cp "$TARGET_FILE" "$BACKUP_FILE"
fi

# Copy new file
print_info "Installing huawei.py to $TARGET_DIR/"
cp huawei.py "$TARGET_FILE"
chmod 644 "$TARGET_FILE"
print_success "File installed"

# Step 3: Configure Modbus settings
print_header "Step 3: Configure Modbus Settings"

print_info "Setting Modbus device configuration..."
dbus -y com.victronenergy.settings /Settings/ModbusClient/${DEVICE}/Devices SetValue "rtu:${DEVICE}:9600:1" >/dev/null 2>&1
print_success "Device configuration: rtu:${DEVICE}:9600:1"

print_info "Enabling auto-scan..."
dbus -y com.victronenergy.settings /Settings/ModbusClient/${DEVICE}/AutoScan SetValue 1 >/dev/null 2>&1
print_success "Auto-scan enabled"

# Step 4: Clear cache
print_header "Step 4: Clear Python Cache"

print_info "Removing Python bytecode cache..."
rm -rf ${TARGET_DIR}/__pycache__/huawei* 2>/dev/null
rm -rf ${TARGET_DIR}/__pycache__/* 2>/dev/null
print_success "Cache cleared"

# Step 5: Restart services
print_header "Step 5: Restart Services"

print_info "Stopping existing services on $DEVICE..."
# Stop all potential services on this device
for service in /service/*${DEVICE}*; do
    if [ -e "$service" ]; then
        svc -d "$service" 2>/dev/null || true
        print_success "Stopped $(basename $service)"
    fi
done

print_info "Restarting serial-starter..."
svc -t /service/serial-starter
print_success "Serial-starter restarted"

# Step 6: Wait for device detection
print_header "Step 6: Waiting for Device Detection"

print_info "Waiting 30 seconds for device to be detected..."
echo -n "Progress: "
for i in {1..30}; do
    echo -n "."
    sleep 1
    
    # Check every 5 seconds if device appeared
    if [ $((i % 5)) -eq 0 ]; then
        if dbus -y 2>/dev/null | grep -q "huawei_sun2000"; then
            echo ""
            print_success "Device detected early!"
            break
        fi
    fi
done
echo ""

# Step 7: Verify installation
print_header "Step 7: Verification"

print_info "Checking if Huawei device is registered on D-Bus..."
if dbus -y 2>/dev/null | grep -q "huawei_sun2000"; then
    print_success "Device found: com.victronenergy.pvinverter.huawei_sun2000"
    
    # Show some data
    echo ""
    print_info "Current values:"
    
    # Position
    POSITION=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Position GetValue 2>/dev/null || echo "N/A")
    echo "  Position: $POSITION (1 = AC Output)"
    
    # Lifetime Energy
    YIELD=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Yield/Power GetValue 2>/dev/null || echo "N/A")
    echo "  Lifetime Total: $YIELD kWh"
    
    # AC Power
    POWER=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Ac/Power GetValue 2>/dev/null || echo "N/A")
    echo "  AC Power: $POWER W"
    
    # Status Code
    STATUS=$(dbus -y com.victronenergy.pvinverter.huawei_sun2000 /StatusCode GetValue 2>/dev/null || echo "N/A")
    echo "  Status Code: $STATUS"
    
    # Check if system sees PV
    echo ""
    print_info "Checking system integration..."
    PV_POWER=$(dbus -y com.victronenergy.system /Ac/PvOnOutput/L1/Power GetValue 2>/dev/null || echo "N/A")
    if [ "$PV_POWER" != "N/A" ] && [ "$PV_POWER" != "[]" ]; then
        print_success "System recognizes PV inverter (L1 Power: $PV_POWER W)"
    else
        print_warning "System not yet recognizing PV (might need a few more seconds)"
    fi
    
else
    print_error "Device not detected on D-Bus!"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check logs: tail -n 100 /var/log/dbus-modbus-client.${DEVICE}/current | tai64nlocal"
    echo "  2. Verify wiring (Pin 5=GND, 7=A, 9=B)"
    echo "  3. Check inverter settings (Slave mode, 9600 baud)"
    echo "  4. Verify device: ls -l /dev/$DEVICE"
    exit 1
fi

# Step 8: Final instructions
print_header "✅ Installation Complete!"

echo "The Huawei SUN2000 integration is now installed and running."
echo ""
echo "Next steps:"
echo "  1. Check Victron GUI - Device List for 'Huawei SUN2000'"
echo "  2. Verify data in System Overview"
echo "  3. Check VRM Portal for uploaded data"
echo ""
echo "Configuration details:"
echo "  Device: /dev/$DEVICE"
echo "  Baud rate: 9600"
echo "  Protocol: Modbus RTU"
echo "  D-Bus service: com.victronenergy.pvinverter.huawei_sun2000"
echo ""
echo "To monitor in real-time:"
echo "  dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue"
echo ""
echo "To check logs:"
echo "  tail -f /var/log/dbus-modbus-client.${DEVICE}/current | tai64nlocal"
echo ""
print_success "Installation completed successfully! ☀️"
