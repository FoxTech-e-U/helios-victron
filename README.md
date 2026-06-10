# ☀️ Helios-Victron

**Huawei SUN2000 Modbus RTU Integration for Victron Energy GX Devices**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Victron Venus OS](https://img.shields.io/badge/Victron-Venus%20OS%203.70+-blue)](https://www.victronenergy.com/)
[![Huawei SUN2000](https://img.shields.io/badge/Huawei-SUN2000-red)](https://solar.huawei.com/)
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

Integration plugin for connecting Huawei SUN2000 series inverters to Victron Energy GX devices (Cerbo GX, Venus GX, etc.) via Modbus RTU (RS485).

## 🌟 Features

- ✅ **Full 3-Phase Support** — Voltage, Current, and Power per phase
- ✅ **Line Voltages** — L1-L2, L2-L3, L1-L3
- ✅ **Energy Monitoring** — Daily yield and lifetime total energy
- ✅ **DC Metrics** — DC voltage, current, and power from solar panels
- ✅ **Temperature & Efficiency** — Internal inverter temperature and efficiency
- ✅ **Native Integration** — Appears as PV Inverter in Victron dashboard and VRM
- ✅ **Venus OS 3.70+** — Compatible with read-only filesystem via symlink + rc.local

## 📋 Compatibility

### Tested Hardware
- **Inverter**: Huawei SUN2000-8KTL-M1 (Model ID: 428)
- **GX Device**: Cerbo GX (Venus OS v3.70)
- **Interface**: FTDI FT232R USB-RS485 adapter
- **Shared bus**: ABB Terra AC 16A wallbox on same RS485 bus

### Potentially Compatible Models
Any SUN2000 series inverter supporting Modbus RTU. Add your Model ID to the `models` dict in `huawei.py` and submit a pull request!

To find your Model ID:
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

### Register Mapping
Based on **SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)**.
See [docs/REGISTERS.md](docs/REGISTERS.md) for complete reference.

## ⚠️ Important Notes

### SDongle and RS485 are mutually exclusive
The Huawei SDongle (WLAN) and RS485 **cannot be used simultaneously**. When the SDongle is plugged in, it takes control of the internal RS485 bus and external RS485 communication fails.

**→ Unplug the SDongle before using RS485.**

After unplugging the SDongle, **power-cycle the inverter** (AC breaker off, wait 2 minutes, back on) to reinitialize the RS485 stack.

### After any Huawei firmware update
The RS485 stack can hang after a firmware update even if settings appear correct.
**→ Power-cycle the inverter** to restore RS485 communication.

### Venus OS 3.70+ compatibility
Venus OS 3.70 introduced a **read-only root filesystem**. Plugins can no longer be placed directly in `/opt/victronenergy/`. The install script handles this automatically using:
1. Plugin stored in `/data/helios-victron/` (persistent, survives updates)
2. Symlink from `/opt/victronenergy/dbus-modbus-client/` to `/data/`
3. `import huawei` patched into `dbus-modbus-client.py`
4. `rc.local` restores symlink and import patch after every firmware update

## 🔌 Hardware Connection

### Wiring
```
Huawei SUN2000 (COM Port)          RS485-USB Adapter
┌─────────────────────┐           ┌──────────────┐
│ Pin 5: GND   ──────────────────→│ GND          │
│ Pin 7: DATA+ (A) ──────────────→│ A / DATA+    │
│ Pin 9: DATA- (B) ──────────────→│ B / DATA-    │
└─────────────────────┘           └──────────────┘
                                         │ USB
                                  Cerbo GX USB Port
```

### Inverter Configuration (SUN2000 App)
Connect to the inverter's own WLAN hotspot (active ~3 min after power-on).
Login as **Installer** (default password: `00000a`).

Navigate to: `Settings → Communication → RS485_1`

| Parameter | Value |
|-----------|-------|
| Mode | Slave |
| Baud Rate | 9600 |
| Data Bits | 8 |
| Parity | None |
| Stop Bits | 1 |
| Address | 1 |

## 🚀 Installation

### One-line install (recommended)
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
bash /tmp/install.sh ttyUSB1
```

### Update to latest version
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
bash /tmp/install.sh ttyUSB1
```

### What the installer does
1. Downloads `huawei.py` from GitHub (or uses local copy if present)
2. Installs to `/data/helios-victron/` (survives firmware updates)
3. Creates symlink in `/opt/victronenergy/dbus-modbus-client/`
4. Patches `import huawei` into `dbus-modbus-client.py`
5. Adds `rc.local` entries to auto-restore everything after firmware updates
6. Configures auto-scan on the specified USB device
7. Waits for device detection and verifies

## 📊 Available D-Bus Data Points

After installation, the inverter appears as `com.victronenergy.pvinverter.huawei_sun2000`:

| Path | Unit | Description |
|------|------|-------------|
| `/Ac/Power` | W | Total AC output power |
| `/Ac/Frequency` | Hz | Grid frequency |
| `/Ac/Energy/Forward` | kWh | Daily energy yield |
| `/Yield/Power` | kWh | Lifetime total energy |
| `/Ac/L1/Voltage` | V | Phase A voltage |
| `/Ac/L2/Voltage` | V | Phase B voltage |
| `/Ac/L3/Voltage` | V | Phase C voltage |
| `/Ac/L1L2/Voltage` | V | Line voltage A-B |
| `/Ac/L2L3/Voltage` | V | Line voltage B-C |
| `/Ac/L1L3/Voltage` | V | Line voltage C-A |
| `/Ac/L1/Current` | A | Phase A current |
| `/Ac/L2/Current` | A | Phase B current |
| `/Ac/L3/Current` | A | Phase C current |
| `/Ac/L1/Power` | W | Phase A power (Total/3) |
| `/Dc/0/Voltage` | V | PV string voltage |
| `/Dc/0/Current` | A | PV string current |
| `/Dc/0/Power` | W | PV input power |
| `/StatusCode` | - | Device status (see REGISTERS.md) |
| `/ErrorCode` | - | Fault code (0 = no fault) |
| `/Temperature` | °C | Internal temperature |
| `/Efficiency` | % | Inverter efficiency |

## 🔧 Monitoring & Troubleshooting

```bash
# Live data
dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue

# Service status
svstat /service/dbus-modbus-client.serial.ttyUSB1

# Logs
tail -f /var/log/dbus-modbus-client.ttyUSB1/current | tai64nlocal

# Test RS485 directly
python3 -c "
from pymodbus.client.sync import ModbusSerialClient; import time
c = ModbusSerialClient(method='rtu', port='/dev/ttyUSB1', baudrate=9600,
    bytesize=8, parity='N', stopbits=1, timeout=3)
c.connect(); time.sleep(1)
r = c.read_holding_registers(32089, 1, unit=1)
print('Status:', hex(r.registers[0]) if hasattr(r,'registers') else 'no response')
c.close()"
```

### StatusCode values
| Value | Hex | Description |
|-------|-----|-------------|
| 512 | 0x0200 | On-grid (running normally) |
| 256 | 0x0100 | Starting |
| 768 | 0x0300 | Fault shutdown |
| 40960 | 0xA000 | Standby: no irradiation (night) |

## 🤝 Contributing

Contributions welcome! Especially:
- Testing with other SUN2000 models → add Model IDs
- Testing with other Venus OS versions

## 📜 License

GPL-3.0 — see [LICENSE](LICENSE)

## 🙏 Acknowledgments

- Victron Energy for the open GX platform
- [dbus-huaweisun2000-pvinverter](https://github.com/kcbam/dbus-huaweisun2000-pvinverter) — inspiration
- Community contributors and testers

## ⚠️ Disclaimer

Provided "as-is" without warranty. Use at your own risk.

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/FoxTech-e-U/helios-victron/issues)
- **Buy Me a Coffee**: [!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

---

**Named after Helios** ☀️ — the Greek god of the Sun.
Sister project: [helios-ev](https://github.com/FoxTech-e-U/helios-ev) — ABB Terra AC wallbox integration

