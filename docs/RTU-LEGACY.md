# Legacy: Modbus RTU Installation

> ⚠️ **This is no longer the recommended installation method.** See the main
> [README](../README.md) for why this project moved to Modbus TCP. This document
> is kept for anyone with a confirmed-stable RS485 setup who wants to keep using RTU,
> or who wants to try RTU first before deciding to switch to TCP.

## When RTU might still work for you

RTU reliability appears to depend heavily on the physical condition of the Huawei
COM port itself, not on general RS485 wiring quality. If you already have a wallbox
or other RS485 device sharing the same cable run and it stays reliable while the
Huawei does not, that's a strong signal the issue is the Huawei port — TCP will
very likely be more stable for you too.

If you haven't tested yet and want to try RTU first, follow this guide. If you see
intermittent "no response" errors that come and go without a clear cause (not fixed
by re-wiring, re-terminating, or power-cycling), switch to TCP rather than
continuing to troubleshoot RTU — this is the exact symptom that led us to move away
from it.

## Hardware Connection

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

⚠️ If you get no response at all, try swapping A and B — some installations have
these reversed relative to what the inverter label suggests.

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

## ⚠️ SDongle and RS485 are mutually exclusive

The Huawei SDongle (WLAN) and RS485 **cannot be used simultaneously**. When the
SDongle is plugged in, it interferes with external RS485 communication even if
it isn't actively being polled over TCP. **Unplug the SDongle before using RTU.**

After unplugging, power-cycle the inverter (AC breaker off, wait 2 minutes, back
on) to reinitialize the RS485 stack.

## Installation

```bash
wget -O /tmp/install-rtu.sh https://raw.githubusercontent.com/FoxTech-e-U/helios-victron/master/install-rtu.sh
bash /tmp/install-rtu.sh ttyUSB1
```

### What the installer does
1. Downloads `huawei.py` from GitHub (or uses local copy if present)
2. Installs to `/data/helios-victron/` (survives firmware updates)
3. Creates a symlink in `/opt/victronenergy/dbus-modbus-client/`
4. Patches `import huawei` into `dbus-modbus-client.py` (required since
   `dbus-modbus-client` v1.80 no longer auto-discovers plugins)
5. Adds `rc.local` entries to restore the symlink and import after firmware updates
6. Configures auto-scan on the specified USB device

## Register Mapping

Based on **SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)**.
See [REGISTERS.md](REGISTERS.md) for the complete reference — it applies
identically to both RTU and TCP, only the transport differs.

## Troubleshooting

### No response / intermittent failures
1. Confirm the SDongle is unplugged
2. Power-cycle the inverter (AC breaker off, 2 min, back on)
3. Try swapping A/B
4. Check the connection at the inverter's COM terminal is firmly seated
5. If failures persist without a clear pattern — **this is the signal to switch to TCP**,
   not a wiring problem to keep chasing

### After any Huawei firmware update
The RS485 stack can hang after a firmware update even with correct settings.
Power-cycle the inverter to restore communication.

### Device not found on shared RS485 bus
If another device (e.g. ABB Terra AC) also shares the bus, ensure both are listed
in the Modbus device config:
```bash
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices \
    SetValue "rtu:ttyUSB1:9600:1,rtu:ttyUSB1:9600:2"
svc -t /service/dbus-modbus-client.serial.ttyUSB1
```

## Migrating to TCP

If RTU is giving you trouble, see the main [README](../README.md) for the TCP
installation. Both methods register the same D-Bus service name
(`com.victronenergy.pvinverter.huawei_sun2000`) — running both at once creates a
conflict. The TCP installer detects and automatically removes the RTU plugin;
if migrating manually, remove the RTU plugin first:

```bash
mount -o remount,rw /
sed -i '/^import huawei$/d' /opt/victronenergy/dbus-modbus-client/dbus-modbus-client.py
rm -f /opt/victronenergy/dbus-modbus-client/huawei.py
mount -o remount,ro /
dbus -y com.victronenergy.settings /Settings/ModbusClient/ttyUSB1/Devices \
    SetValue ""   # or leave only other devices, e.g. "rtu:ttyUSB1:9600:2" for an ABB Terra
svc -t /service/dbus-modbus-client.serial.ttyUSB1
```
