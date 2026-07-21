# ☀️ Helios-Victron

**Huawei SUN2000 Modbus TCP Integration for Victron Energy GX Devices**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Victron Venus OS](https://img.shields.io/badge/Victron-Venus%20OS%203.70+-blue)](https://www.victronenergy.com/)
[![Huawei SUN2000](https://img.shields.io/badge/Huawei-SUN2000-red)](https://solar.huawei.com/)
[!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

Integration for connecting Huawei SUN2000 series inverters to Victron Energy GX devices (Cerbo GX, Venus GX, etc.) via Modbus TCP through the Huawei SDongle.

## ⚠️ Why Modbus TCP instead of RTU

This project originally used Modbus RTU (RS485). **We moved to Modbus TCP** after extensive
troubleshooting revealed that RTU communication with the Huawei COM port was unreliable in
practice — inconsistent responses, frequent hangs after Cerbo reboots or Huawei firmware
updates, and behavior that pointed to marginal signal quality at the physical COM port itself
(not the cabling or the RS485 bus, which stayed fully reliable for a co-located ABB Terra AC
wallbox on the same cable run).

Modbus TCP via the SDongle proved consistently stable in comparison. If you have a working
RTU setup, you're welcome to keep using it — the legacy `huawei.py` RTU plugin for
`dbus-modbus-client` is still included in this repo for that purpose. But **TCP is now the
recommended and actively maintained path.**

### Key differences from RTU
- Runs as an **independent Python daemon** (`helios-huawei-tcp.py`), not a `dbus-modbus-client` plugin
- Registers its own D-Bus service directly using Victron's `VeDbusService`
- Opens a **fresh TCP connection for every register block** — the SDongle only tolerates a
  few consecutive requests per connection before dropping it
- RS485 (RTU) and the SDongle **cannot be used simultaneously** — if you switch to TCP,
  physically remove the RS485 connection to the Huawei COM port (other devices, like an ABB
  Terra AC wallbox, can keep using RS485 independently on the same bus)

## 🌟 Features

- ✅ Full 3-phase AC data — voltage, current, power per phase
- ✅ DC input monitoring — PV string voltage, current, power
- ✅ Energy monitoring — daily yield and lifetime total
- ✅ Temperature & efficiency
- ✅ Native Victron dashboard and VRM Portal integration
- ✅ Independent of `dbus-modbus-client` — survives its version changes
- ✅ Venus OS 3.70+ compatible (read-only filesystem via `/data/` + rc.local)

## 📋 Compatibility

### Tested Hardware
- **Inverter**: Huawei SUN2000-8KTL-M1 (Model ID: 428)
- **GX Device**: Cerbo GX (Venus OS v3.70)
- **Dongle**: Huawei SDongle-A (WLAN), fixed IP via DHCP reservation

## 🔌 Network Setup

1. Give the SDongle a **fixed/reserved IP** on your network (DHCP reservation recommended)
2. Enable Modbus TCP on the inverter (SUN2000 App → Installer login → Communication → Modbus TCP)
   - Default port: **502**
   - Modbus unit/slave ID: **1**
3. Confirm the Cerbo GX and the dongle are on the same network/VLAN

### Verify connectivity
```bash
python3 -c "
from pymodbus.client.sync import ModbusTcpClient
c = ModbusTcpClient('<dongle-ip>', port=502, timeout=5)
print('Connected:', c.connect())
r = c.read_holding_registers(30070, 1, unit=1)
print('Model ID:', r.registers[0] if hasattr(r,'registers') else 'no response')
c.close()"
```

## 🚀 Installation

### One-line install (recommended)
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
bash /tmp/install.sh <dongle-ip>
```

### What the installer does
1. Downloads `helios-huawei-tcp.py` from GitHub (or uses local copy if present)
2. Installs to `/data/helios-victron/` (survives firmware updates)
3. Sets the dongle IP in the daemon config
4. Installs and starts a runit service (`/service/helios-huawei-tcp`)
5. Adds `rc.local` entries to restore the service after firmware updates
6. If a legacy RTU `huawei.py` plugin is detected on `ttyUSB*`, removes it and its
   `dbus-modbus-client.py` import to avoid a duplicate/conflicting D-Bus service

### Manual installation
```bash
mkdir -p /data/helios-victron
cp helios-huawei-tcp.py /data/helios-victron/
chmod 755 /data/helios-victron/helios-huawei-tcp.py

# Edit DONGLE_IP at the top of the file to match your setup

mkdir -p /service/helios-huawei-tcp/log
cat > /service/helios-huawei-tcp/run << 'RUNEOF'
#!/bin/sh
exec /usr/bin/python3 -u /data/helios-victron/helios-huawei-tcp.py 2>&1
RUNEOF
cat > /service/helios-huawei-tcp/log/run << 'LOGEOF'
#!/bin/sh
exec multilog t s25000 n4 /var/log/helios-huawei-tcp
LOGEOF
chmod 755 /service/helios-huawei-tcp/run
chmod 755 /service/helios-huawei-tcp/log/run
```

## ⚙️ Configuration

Edit the top of `helios-huawei-tcp.py`:

```python
DONGLE_IP        = '172.20.0.186'   # your SDongle's fixed IP
DONGLE_PORT      = 502
MODBUS_UNIT      = 1
POLL_INTERVAL    = 10                # seconds between full poll cycles
CONNECT_TIMEOUT  = 2                 # seconds per register block
DEVICE_INSTANCE  = 20
```

## 📊 Available D-Bus Data Points

Service: `com.victronenergy.pvinverter.huawei_sun2000`

| Path | Unit | Description |
|------|------|-------------|
| `/Ac/Power` | W | Total AC output power |
| `/Ac/Frequency` | Hz | Grid frequency |
| `/Ac/Energy/Forward` | kWh | Daily energy yield |
| `/Yield/Power` | kWh | Lifetime total energy |
| `/Ac/L1/Voltage`, `L2`, `L3` | V | Phase voltages |
| `/Ac/L1/Current` | A | Phase A current |
| `/Ac/L1/Power`, `L2`, `L3` | W | Per-phase power (Total/3 estimate) |
| `/Dc/0/Voltage` | V | PV string voltage |
| `/Dc/0/Current` | A | PV string current |
| `/Dc/0/Power` | W | PV input power |
| `/StatusCode` | - | Device status (see below) |
| `/ErrorCode` | - | Fault code (0 = no fault) |
| `/Temperature` | °C | Internal temperature |
| `/Efficiency` | % | Inverter efficiency |

### StatusCode values
| Value | Hex | Description |
|-------|-----|-------------|
| 512 | 0x0200 | On-grid (running normally) |
| 256 | 0x0100 | Starting |
| 768 | 0x0300 | Fault shutdown |
| 40960 | 0xA000 | Standby: no irradiation (night) |

Note: many registers return no value (`[]` on D-Bus) at night/standby — this is expected,
not an error. The inverter simply doesn't respond to those registers outside normal operation.

## 🔧 Monitoring & Troubleshooting

```bash
# Live data
dbus -y com.victronenergy.pvinverter.huawei_sun2000 / GetValue

# Service status
svstat /service/helios-huawei-tcp

# Logs
tail -f /var/log/helios-huawei-tcp/current | tai64nlocal
```

### Poll cycle taking a long time / low register count
Normal at night — unanswered registers each wait out `CONNECT_TIMEOUT` before moving on.
During the day with the inverter active, expect most/all of the ~14 register groups to
respond and cycle times to drop significantly.

### No registers responding at all
```bash
# Test the dongle directly
python3 -c "
from pymodbus.client.sync import ModbusTcpClient
c = ModbusTcpClient('<dongle-ip>', port=502, timeout=5)
print('Connected:', c.connect())
c.close()"
```
If this fails: check the dongle's IP hasn't changed, and that Modbus TCP is still enabled
in the SUN2000 App.

### After Venus OS update
`rc.local` restores the service automatically on boot. If it doesn't come back:
```bash
wget -O /tmp/install.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install.sh
bash /tmp/install.sh <dongle-ip>
```

## 📜 Legacy: RTU Plugin

The original `huawei.py` RTU plugin for `dbus-modbus-client` remains in this repo for anyone
with a stable RS485 setup. See [docs/RTU-LEGACY.md](docs/RTU-LEGACY.md) for its installation
instructions. It is no longer the primary supported path.

## 🤝 Contributing

Contributions welcome, especially:
- Testing with other SUN2000 models
- Testing with other Venus OS versions
- Reports on RTU vs TCP reliability on different hardware

## 📜 License

GPL-3.0 — see [LICENSE](LICENSE)

## 🙏 Acknowledgments

- Victron Energy for the open GX platform
- Community contributors and testers

## ⚠️ Disclaimer

Provided "as-is" without warranty. Use at your own risk.

## 📧 Support

- **Issues**: [GitHub Issues](https://github.com/FoxTech-e-U/helios-victron/issues)
- **Buy Me a Coffee**: [!["Buy Me A Coffee"](https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png)](https://buymeacoffee.com/olli_foxtech)

---

**Named after Helios** ☀️ — the Greek god of the Sun.
Sister project: [helios-ev](https://github.com/FoxTech-e-U/helios-ev) — ABB Terra AC wallbox integration
