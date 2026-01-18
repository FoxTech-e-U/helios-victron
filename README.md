# ☀️ Helios-Victron

**Huawei SUN2000 Modbus RTU Integration for Victron Energy GX Devices**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Victron Venus OS](https://img.shields.io/badge/Victron-Venus%20OS-blue)](https://www.victronenergy.com/)
[![Huawei SUN2000](https://img.shields.io/badge/Huawei-SUN2000-red)](https://solar.huawei.com/)
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

Integration plugin for connecting Huawei SUN2000 series inverters to Victron Energy GX devices (Cerbo GX, Venus GX, etc.) via Modbus RTU (RS485).

## 🌟 Features

- ✅ **Full 3-Phase Support** - Voltage, Current, and Power per phase
- ✅ **Energy Monitoring** - Daily yield and lifetime total energy
- ✅ **DC Metrics** - DC voltage, current, and power from solar panels
- ✅ **Native Integration** - Appears as PV Inverter in Victron system
- ✅ **VRM Portal Support** - All data visible in Victron Remote Management
- ✅ **Status Monitoring** - Inverter status codes and error reporting
- ✅ **Automatic Discovery** - Auto-detected by Victron's modbus-client

## 📋 Compatibility

### Tested Hardware
- **Inverter**: Huawei SUN2000-8KTL-M1 (Model ID: 428)
- **GX Device**: Cerbo GX (Venus OS v3.x)
- **Interface**: RS485 to USB adapter

### Potentially Compatible Models
This plugin should work with other SUN2000 series inverters that support Modbus RTU. You may need to add your model ID to the `models` dictionary in `huawei.py`.

## 🔌 Hardware Connection

### Required Hardware
1. Huawei SUN2000 inverter with RS485 interface
2. Victron GX device (Cerbo GX, Venus GX, etc.)
3. RS485 to USB adapter

### Wiring Diagram

```
Huawei SUN2000 (COM Port)          RS485-USB Adapter
┌─────────────────────┐           ┌──────────────┐
│ Pin 5: GND   ──────────────────→│ GND          │
│ Pin 7: DATA+ (A) ──────────────→│ A / DATA+    │
│ Pin 9: DATA- (B) ──────────────→│ B / DATA-    │
└─────────────────────┘           └──────────────┘
                                         │
                                         ↓ USB
                                  Cerbo GX USB Port
```

### Pin Configuration
- **Pin 5**: Ground (GND)
- **Pin 7**: RS485 Data+ (A)
- **Pin 9**: RS485 Data- (B)

⚠️ **Important**: Check your inverter's manual for the exact COM port pinout!

## ⚙️ Inverter Configuration

### Enable Modbus RTU on Huawei SUN2000

1. **Access Inverter Interface**
   - Connect to inverter via WLAN or FusionSolar app
   - Login with installer/maintainer credentials

2. **Configure RS485 Settings**
   - Navigate to: `Settings` → `Communication` → `RS485`
   - Set **Mode**: `Slave` (NOT Master!)
   - Set **Baud Rate**: `9600`
   - Set **Data Bits**: `8`
   - Set **Parity**: `None`
   - Set **Stop Bits**: `1`
   - Set **Device Address**: `1` (default)

3. **Save and Reboot**
   - Apply settings
   - Reboot inverter to activate Modbus interface

## 🚀 Installation

### Quick Installation (Recommended)

We provide an automated installation script that handles everything for you:

```bash
# 1. Download the repository
wget https://github.com/FoxTech-e-U/helios-victron/archive/refs/heads/main.zip
unzip main.zip
cd helios-victron-main

# 2. Run the installation script
chmod +x install.sh
./install.sh

# The script will:
# - Help you identify the correct USB device
# - Install the huawei.py plugin
# - Configure Modbus settings automatically
# - Restart services and verify the installation
```

The installation script is interactive and will guide you through each step!

### Manual Installation

If you prefer manual installation or need more control, follow these steps:

#### Step 1: Access Cerbo GX via SSH

```bash
# Enable SSH access in Cerbo GX settings first and set root password
ssh root@<cerbo-ip-address>
```

#### Step 2: Download Files

```bash
# Download the repository
cd /tmp
wget https://github.com/FoxTech-e-U/helios-victron/archive/refs/heads/main.zip
unzip main.zip
cd helios-victron-main
```

#### Step 3: Identify USB Device

```bash
# List USB serial devices
ls -l /dev/ttyUSB*

# You should see something like:
# /dev/ttyUSB0  (might be your EM540 or other device)
# /dev/ttyUSB1  (your Huawei inverter)
```

⚠️ **Important**: Note which `ttyUSBX` is your Huawei inverter!

#### Step 4: Install the Plugin

```bash
# Copy huawei.py to modbus-client directory
cp huawei.py /opt/victronenergy/dbus-modbus-client/
chmod 644 /opt/victronenergy/dbus-modbus-client/huawei.py
```

#### Step 5: Configure Modbus Settings

```bash
# Replace ttyUSB1 with your actual device!
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices SetValue "rtu:ttyUSB1:9600:1"
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/AutoScan SetValue 1
```

#### Step 6: Restart Services

```bash
# Clear Python cache
rm -rf /opt/victronenergy/dbus-modbus-client/__pycache__/*

# Restart serial-starter
svc -t /service/serial-starter

# Wait for device detection (30-60 seconds)
sleep 30

# Check if device is detected
dbus -y | grep huawei
```

You should see:
```
com.victronenergy.pvinverter.huawei_sun2000
```

#### Step 7: Verify Installation

```bash
# Check all values
dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue

# Check if system sees PV inverter
dbus -y com.victronenergy.system /Ac/PvOnOutput/L1/Power GetValue
```

### Detailed Installation Guide

For a complete step-by-step guide with troubleshooting, see [docs/INSTALLATION.md](docs/INSTALLATION.md)

## 📊 Available Data Points

### AC Output
- **Total Power**: `/Ac/Power` (W)
- **Frequency**: `/Ac/Frequency` (Hz)
- **Daily Energy**: `/Ac/Energy/Forward` (kWh) - Today's production
- **Lifetime Total**: `/Yield/Power` (kWh) - Total since installation

### Per Phase (L1, L2, L3)
- **Voltage**: `/Ac/L1/Voltage`, `/Ac/L2/Voltage`, `/Ac/L3/Voltage` (V)
- **Current**: `/Ac/L1/Current`, `/Ac/L2/Current`, `/Ac/L3/Current` (A)
- **Power**: `/Ac/L1/Power`, `/Ac/L2/Power`, `/Ac/L3/Power` (W)

### DC Input (Solar Panels)
- **Voltage**: `/Dc/0/Voltage` (V)
- **Current**: `/Dc/0/Current` (A)
- **Power**: `/Dc/0/Power` (W)

### Status
- **Status Code**: `/StatusCode` - Inverter operational status
- **Error Code**: `/ErrorCode` - Fault codes
- **Position**: `/Position` - 1 = AC Output

## 🔧 Troubleshooting

### Device Not Detected

```bash
# Check if service is running
svstat /service/*ttyUSB*

# Check logs
tail -100 /var/log/dbus-modbus-client.ttyUSB1/current | tai64nlocal

# Look for "Found None: Huawei SUN2000"
```

### Wrong ttyUSB Device

If you picked the wrong USB port:

```bash
# Stop the wrong service
svc -d /service/dbus-modbus-client.ttyUSB1

# Update settings with correct device
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB2/Devices SetValue "rtu:ttyUSB2:9600:1"

# Restart
svc -t /service/serial-starter
```

### Communication Errors

1. **Check wiring** - Verify A/B are not swapped
2. **Check inverter settings** - Must be in Slave mode, 9600 baud
3. **Check cable length** - Keep RS485 cables under 1000m (preferably shorter)

### After Venus OS Update

After a Venus OS update, you may need to reinstall:

```bash
# huawei.py should persist in /opt/victronenergy/dbus-modbus-client/
# But settings might be reset:
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices SetValue "rtu:ttyUSB1:9600:1"
svc -t /service/serial-starter
```

## 📝 Modbus Register Reference

See [docs/REGISTERS.md](docs/REGISTERS.md) for complete register mapping.

## 🤝 Contributing

Contributions are welcome! Please:

1. Test thoroughly on your hardware
2. Document any new inverter models
3. Follow the existing code style
4. Submit pull requests with clear descriptions

## 📜 License

GPL-3.0 License - See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Victron Energy for their excellent GX device platform
- [dbus-huaweisun2000-pvinverter](https://github.com/kcbam/dbus-huaweisun2000-pvinverter) - Inspiration for Modbus TCP approach
- Community contributors and testers

## ⚠️ Disclaimer

This software is provided "as-is" without warranty. Use at your own risk. 
The author is not responsible for any damage to equipment or loss of data.

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/FoxTech-e-U/helios-victron/issues)
- **Discussions**: [GitHub Discussions](https://github.com/FoxTech-e-U/helios-victron/discussions)
- **Buy Me a Coffee**: [!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)
---

**Named after Helios** ☀️ - The Greek god of the Sun, who drove his chariot across the sky each day, bringing light and energy to the world.
