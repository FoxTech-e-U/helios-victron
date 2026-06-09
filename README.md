# ☀️ Helios-Victron

**Huawei SUN2000 Modbus RTU Integration for Victron Energy GX Devices**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Victron Venus OS](https://img.shields.io/badge/Victron-Venus%20OS-blue)](https://www.victronenergy.com/)
[![Huawei SUN2000](https://img.shields.io/badge/Huawei-SUN2000-red)](https://solar.huawei.com/)
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

Integration plugin for connecting Huawei SUN2000 series inverters to Victron Energy GX devices (Cerbo GX, Venus GX, etc.) via Modbus RTU (RS485).

## 🌟 Features

- ✅ **Full 3-Phase Support** - Voltage, Current, and Power per phase
- ✅ **Line Voltages** - L1-L2, L2-L3, L1-L3
- ✅ **Energy Monitoring** - Daily yield and lifetime total energy
- ✅ **DC Metrics** - DC voltage, current, and power from solar panels
- ✅ **Temperature & Efficiency** - Internal inverter temperature and efficiency
- ✅ **Native Integration** - Appears as PV Inverter in Victron system
- ✅ **VRM Portal Support** - All data visible in Victron Remote Management
- ✅ **Status Monitoring** - Inverter status codes and error reporting
- ✅ **Automatic Discovery** - Auto-detected by Victron's modbus-client
- ✅ **Shared RS485 Bus** - Works alongside other devices (e.g. wallboxes)

## 📋 Compatibility

### Tested Hardware
- **Inverter**: Huawei SUN2000-8KTL-M1 (Model ID: 428)
- **GX Device**: Cerbo GX (Venus OS v3.67)
- **Interface**: FTDI FT232R USB-RS485 adapter

### Potentially Compatible Models
This plugin should work with other SUN2000 series inverters that support Modbus RTU.
You may need to add your Model ID to the `models` dictionary in `huawei.py`.

To find your Model ID, run on the Cerbo GX:
```bash
python3 -c "
from pymodbus.client.sync import ModbusSerialClient
c = ModbusSerialClient(method='rtu', port='/dev/ttyUSB1',
    baudrate=9600, bytesize=8, parity='N', stopbits=1, timeout=3)
c.connect()
r = c.read_holding_registers(30070, 1, unit=1)
print('Model ID:', r.registers[0] if hasattr(r,'registers') else 'no response')
c.close()"
```

Then add your model to `huawei.py` and submit a pull request!

### Register Mapping
Based on **SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)**.

## 🔌 Hardware Connection

### Required Hardware
1. Huawei SUN2000 inverter with RS485 interface
2. Victron GX device (Cerbo GX, Venus GX, etc.)
3. RS485 to USB adapter (FTDI-based recommended)

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

### Shared RS485 Bus
Multiple devices can share the same RS485 bus (e.g. Huawei on address 1 + ABB Terra wallbox on address 2). The installation script detects all devices automatically and configures the bus correctly.

## ⚙️ Inverter Configuration

### Enable Modbus RTU on Huawei SUN2000

1. **Access Inverter Interface**
   - Connect via SUN2000 app to the inverter's own WLAN hotspot
     (active for ~3 minutes after power-on)
   - Login as **Installer** (default password: `00000a`)

2. **Configure RS485 Settings**
   - Navigate to: `Settings` → `Communication` → `RS485_1`
   - Set **Mode**: `Slave` (NOT Master!)
   - Set **Baud Rate**: `9600`
   - Set **Data Bits**: `8`
   - Set **Parity**: `None`
   - Set **Stop Bits**: `1`
   - Set **Device Address**: `1` (default)

3. **Save and Reboot**
   - Apply settings and reboot the inverter

## 🚀 Installation

### Quick Installation (Recommended)

```bash
# 1. Download the repository
wget https://github.com/FoxTech-e-U/helios-victron/archive/refs/heads/master.zip
unzip master.zip
cd helios-victron-master

# 2. Run the installation script
chmod +x install.sh
./install.sh

# The script will:
# - Help you identify the correct USB device
# - Scan the RS485 bus for all connected devices
# - Install the huawei.py plugin
# - Configure Modbus settings for all detected devices
# - Restart services and verify the installation
```

### Manual Installation

#### Step 1: Access Cerbo GX via SSH

```bash
ssh root@<cerbo-ip-address>
```

#### Step 2: Download Files

```bash
cd /tmp
wget https://github.com/FoxTech-e-U/helios-victron/archive/refs/heads/master.zip
unzip master.zip
cd helios-victron-master
```

#### Step 3: Install the Plugin

```bash
cp huawei.py /opt/victronenergy/dbus-modbus-client/
chmod 644 /opt/victronenergy/dbus-modbus-client/huawei.py
```

#### Step 4: Configure Modbus Settings

```bash
# Single device (Huawei only):
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices \
    SetValue "rtu:ttyUSB1:9600:1"

# Shared bus (Huawei on addr 1 + another device on addr 2):
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices \
    SetValue "rtu:ttyUSB1:9600:1,rtu:ttyUSB1:9600:2"

dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/AutoScan \
    SetValue 1
```

#### Step 5: Restart Services

```bash
rm -rf /opt/victronenergy/dbus-modbus-client/__pycache__/*
svc -t /service/serial-starter
sleep 30
dbus -y | grep huawei
```

You should see:
```
com.victronenergy.pvinverter.huawei_sun2000
```

#### Step 6: Verify Installation

```bash
dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue
```

## 📊 Available Data Points

### AC Output
| Path | Unit | Description |
|------|------|-------------|
| `/Ac/Power` | W | Total active power |
| `/Ac/Frequency` | Hz | Grid frequency |
| `/Ac/Energy/Forward` | kWh | Daily energy yield |
| `/Yield/Power` | kWh | Lifetime total energy |

### Per Phase (L1, L2, L3)
| Path | Unit | Description |
|------|------|-------------|
| `/Ac/L1/Voltage` | V | Phase voltage |
| `/Ac/L1/Current` | A | Phase current |
| `/Ac/L1/Power` | W | Phase power (estimated as Total/3) |

### Line Voltages
| Path | Unit | Description |
|------|------|-------------|
| `/Ac/L1L2/Voltage` | V | Line voltage A-B |
| `/Ac/L2L3/Voltage` | V | Line voltage B-C |
| `/Ac/L1L3/Voltage` | V | Line voltage C-A |

### DC Input (Solar Panels)
| Path | Unit | Description |
|------|------|-------------|
| `/Dc/0/Voltage` | V | PV string voltage |
| `/Dc/0/Current` | A | PV string current |
| `/Dc/0/Power` | W | PV input power |

### Status & Diagnostics
| Path | Unit | Description |
|------|------|-------------|
| `/StatusCode` | - | Device status (see table below) |
| `/ErrorCode` | - | Fault code (0 = no fault) |
| `/Temperature` | °C | Internal inverter temperature |
| `/Efficiency` | % | Inverter efficiency |

### StatusCode Values
| Value | Hex | Description |
|-------|-----|-------------|
| 0 | 0x0000 | Standby: initialization |
| 256 | 0x0100 | Starting |
| 512 | 0x0200 | On-grid (running normally) |
| 513 | 0x0201 | Grid connected: power limited |
| 768 | 0x0300 | OFF: unexpected shutdown |
| 769 | 0x0301 | OFF: instructed shutdown |
| 771 | 0x0303 | OFF: communication interrupted |
| 40960 | 0xA000 | Standby: no irradiation |

## 🔧 Troubleshooting

### Device Not Detected

```bash
# Check service status
svstat /service/*ttyUSB*

# Check logs
tail -100 /var/log/dbus-modbus-client.ttyUSB1/current | tai64nlocal
```

### No Response After Huawei Firmware Update

⚠️ **Known issue**: After a Huawei SUN2000 firmware update, the RS485 stack
can hang internally. The inverter display may still show correct RS485 settings
but the port does not respond.

**Fix**: Fully power-cycle the inverter:
1. Turn off the AC breaker
2. Wait ~2 minutes for DC capacitors to discharge
3. Power back on

This restores the RS485 interface without changing any settings.

### Communication Errors

1. **Check wiring** - Verify A/B are not swapped (try swapping if no response)
2. **Check inverter settings** - Must be in Slave mode, 9600 baud, address 1
3. **Check bus termination** - 120Ω terminator only at the last device on the bus
4. **Check for competing processes** - Only one process should access the port:
   ```bash
   fuser /dev/ttyUSB1
   ```

### Model ID Not Recognized

If your inverter is detected but shows as unknown model, find and add your Model ID:

```bash
python3 -c "
from pymodbus.client.sync import ModbusSerialClient
c = ModbusSerialClient(method='rtu', port='/dev/ttyUSB1',
    baudrate=9600, bytesize=8, parity='N', stopbits=1, timeout=3)
c.connect()
r = c.read_holding_registers(30070, 1, unit=1)
print('Model ID:', r.registers[0] if hasattr(r,'registers') else 'no response')
c.close()"
```

Add the ID to the `models` dict in `huawei.py` and submit a pull request!

### After Venus OS Update

After a Venus OS update `huawei.py` persists, but settings may be reset:

```bash
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices \
    SetValue "rtu:ttyUSB1:9600:1"
svc -t /service/serial-starter
```

## 📝 Modbus Register Reference

See [docs/REGISTERS.md](docs/REGISTERS.md) for complete register mapping.

## 🤝 Contributing

Contributions are welcome! Please:

1. Test thoroughly on your hardware
2. Document any new inverter Model IDs
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
