# Installation Guide

Complete step-by-step installation guide for Helios-Victron.

## Prerequisites

- Victron GX device (Cerbo GX, Venus GX, etc.) with Venus OS v2.90 or higher
- Huawei SUN2000 inverter with RS485/Modbus RTU support
- RS485 to USB adapter
- SSH access to your GX device

## Part 1: Hardware Setup

### 1.1 Prepare RS485 Cable

You need a cable with 3 wires:
- Ground (GND)
- Data+ (A)
- Data- (B)

**Recommended**: Use twisted pair cable for Data+/Data- to reduce interference.

### 1.2 Connect to Huawei Inverter

1. **Locate the COM port** on your SUN2000 inverter
   - Usually on the bottom or side of the unit
   - Labeled "COM" or "RS485"

2. **Identify pins** (check your inverter manual):
   ```
   Common SUN2000 COM Port Layout:
   1  2  3  4  5  6  7  8  9
   [  ][  ][  ][  ][G][  ][+][  ][-]
                     N     A     B
                     D     /     /
                           D     D
                           A     A
                           T     T
                           A     A
                           +     -
   ```
   - Pin 5: GND
   - Pin 7: DATA+ (A)
   - Pin 9: DATA- (B)

3. **Connect wires**:
   - GND to Pin 5
   - DATA+ to Pin 7
   - DATA- to Pin 9

⚠️ **Important**: Double-check your inverter's manual! Pin layouts may vary.

### 1.3 Connect RS485-USB Adapter

1. **Connect wires to adapter**:
   - GND → GND terminal
   - DATA+ → A (or +) terminal
   - DATA- → B (or -) terminal

2. **Verify polarity**: Some adapters have switches for A/B polarity

3. **Termination resistor**: 
   - Some adapters have built-in 120Ω termination
   - Enable if your cable run is > 10m or you experience errors

### 1.4 Connect to Cerbo GX

1. **Plug USB connector** into Cerbo GX USB port
2. **Wait 10 seconds** for device enumeration
3. **LED indicator**: Adapter LED should blink or light up

## Part 2: Inverter Configuration

### 2.1 Access Inverter Interface

**Option A: Direct WiFi Connection**
1. Connect to inverter's WiFi AP (check inverter display for SSID/password)
2. Open browser to `http://192.168.200.1`
3. Login (default: installer/00000a or see manual)

**Option B: FusionSolar App**
1. Install "FusionSolar" app on smartphone
2. Connect via installer account
3. Navigate to inverter settings

### 2.2 Configure Modbus RTU

Navigate to: **Settings** → **Communication** → **RS485-1** (or **COM**)

Set the following parameters:

| Parameter | Value | Notes |
|-----------|-------|-------|
| Protocol Mode | **Modbus Slave** | NOT Master! |
| Baud Rate | **9600** | Match this in Victron config |
| Data Bits | **8** | Standard |
| Parity | **None** | Standard |
| Stop Bits | **1** | Standard |
| Device Address | **1** | Can be 1, 2, or 3 |

### 2.3 Apply and Reboot

1. **Save settings**: Click "Save" or "Apply"
2. **Reboot inverter**: Power cycle or use interface reboot

⚠️ **Note**: Some inverters require maintenance/installer password to change RS485 settings.

## Part 3: Victron Configuration

### 3.1 Enable SSH Access

1. On Cerbo GX, go to: **Settings** → **General** → **Set root password**
2. Enable **SSH on LAN**
3. Note the IP address shown

⚠️ **Note**: Ensure you enabled SuperUser - unless there is no option to enable SSH

### 3.2 Connect via SSH

```bash
# From your computer
ssh root@192.168.x.x  # Replace with your Cerbo IP

# Enter the password you set
```

### 3.3 Identify USB Device

```bash
# List all USB serial devices
ls -l /dev/ttyUSB*
```

You'll see output like:
```
crw-rw---- 1 root dialout 188, 0 Jan 17 14:05 /dev/ttyUSB0
crw-rw---- 1 root dialout 188, 1 Jan 17 14:05 /dev/ttyUSB1
```

**How to identify which is which:**

**Method 1: Unplug and re-plug**
```bash
# Note which devices are present
ls -l /dev/ttyUSB*

# Unplug Huawei RS485 adapter
# Wait 5 seconds

# Check again - the missing device was the Huawei
ls -l /dev/ttyUSB*
```

**Method 2: Check dmesg**
```bash
dmesg | tail -20
# Look for "USB Serial device" messages
```

**Method 3: Check existing services**
```bash
# See which ttyUSB is already in use
ls -l /service/*ttyUSB*
# Choose a different one for Huawei
```

For this guide, we'll assume **ttyUSB1** is the Huawei inverter.

### 3.4 Install Plugin

```bash
# Navigate to modbus-client directory
cd /opt/victronenergy/dbus-modbus-client/

# Download the plugin
wget https://raw.githubusercontent.com/yggdrasilodin/helios-victron/main/huawei.py

# OR manually create it:
# Copy the contents from huawei.py in this repo
# Paste into: nano huawei.py
# Save with Ctrl+X, Y, Enter

# Verify file exists
ls -l huawei.py

# Should show: -rw-r--r-- 1 root root XXXX Jan XX XX:XX huawei.py
```

### 3.5 Configure Modbus Settings

```bash
# Set device path and parameters
# Replace ttyUSB1 with your actual device!
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices SetValue "rtu:ttyUSB1:9600:1"

# Enable auto-scan
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/AutoScan SetValue 1
```

**Breaking down the device string**:
- `rtu` = Modbus RTU protocol
- `ttyUSB1` = Serial device
- `9600` = Baud rate
- `1` = Modbus device address

### 3.6 Clear Cache and Restart

```bash
# Clear Python bytecode cache
rm -rf /opt/victronenergy/dbus-modbus-client/__pycache__/*

# Restart the serial-starter service
svc -t /service/serial-starter

# Wait for device detection (can take 30-60 seconds)
echo "Waiting for device detection..."
sleep 45
```

### 3.7 Verify Detection

```bash
# Check if Huawei device appeared on D-Bus
dbus -y | grep huawei
```

**Expected output**:
```
com.victronenergy.pvinverter.huawei_sun2000
```

**If not found**: Continue to troubleshooting section.

### 3.8 Check Data

```bash
# View all available data
dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue

# Check specific values
dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Yield/Power GetValue
dbus -y com.victronenergy.pvinverter.huawei_sun2000 /Position GetValue
```

**Expected output** (values will vary):
```
21382.07  # Lifetime energy in kWh
1         # Position (1 = AC Output)
```

### 3.9 Verify System Integration

```bash
# Check if Victron system recognizes the PV inverter
dbus -y com.victronenergy.system /Ac/PvOnOutput/L1/Power GetValue
```

Should return current power (e.g., `0.0` at night, or actual value during day).

## Part 4: Verification

### 4.1 Check Victron GUI

1. **On Cerbo GX**:
   - Navigate to **Device List**
   - Should see "Huawei SUN2000" listed
   - Click to see detailed values

2. **Verify Values**:
   - AC Power: Current production (W)
   - Energy (Today): Daily yield (kWh)
   - Phases: L1, L2, L3 voltages and currents

3. **System Overview**:
   - PV inverter should appear in system diagram
   - Energy flows should be visible

### 4.2 Check VRM Portal

1. Login to **VRM Portal** (vrm.victronenergy.com)
2. Select your installation
3. Check **Device List** for Huawei inverter
4. View **Advanced** widgets for detailed metrics

### 4.3 Test Data Updates

Wait for sunrise (when inverter is producing):
- Values should update every few seconds or at least every second - it is really fast
- Daily energy should increment
- Lifetime total should be stable (changes only daily or maybe increases during the day)

## Part 5: Make It Persistent

The plugin file `/opt/victronenergy/dbus-modbus-client/huawei.py` should persist across reboots.

**To verify persistence:**

```bash
# Reboot the Cerbo GX
reboot

# After reboot, SSH back in and check:
dbus -y | grep huawei
```

Device should reappear automatically.

## Troubleshooting

See main [README.md](../README.md#troubleshooting) for detailed troubleshooting steps.

### Quick Checks

**Device not detected?**
```bash
# Check logs for errors
tail -100 /var/log/dbus-modbus-client.ttyUSB1/current | tai64nlocal | grep -E "ERROR|huawei|Found"
```

**Wrong ttyUSB?**
```bash
# Stop wrong service
svc -d /service/dbus-modbus-client.ttyUSB1

# Reconfigure with correct device
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB2/Devices SetValue "rtu:ttyUSB2:9600:1"
svc -t /service/serial-starter
```

**Communication errors?**
```bash
# Test manual Modbus read
# This requires pymodbus package (may not be available on stock Venus OS)

# Check if data is being received
svstat /service/dbus-modbus-client.ttyUSB1
tail -f /var/log/dbus-modbus-client.ttyUSB1/current | tai64nlocal
```

## Next Steps

- Set up monitoring dashboards in VRM
- Configure energy management rules
- Set up alerts for inverter errors
- Integrate with other Victron devices

## Support

- Report issues: [GitHub Issues](https://github.com/YOUR-USERNAME/helios-victron/issues)
- Ask questions: [GitHub Discussions](https://github.com/YOUR-USERNAME/helios-victron/discussions)
- Buy Me a Coffee: [!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

