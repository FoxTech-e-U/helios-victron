# Modbus Register Reference

Complete Modbus register mapping for Huawei SUN2000 inverters.

Based on: **SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)**

## Register Overview

| Address | Type | R/W | Description | Unit | Gain | D-Bus Path |
|---------|------|-----|-------------|------|------|------------|
| 30000 | STR | RO | Model name | - | - | - |
| 30070 | U16 | RO | Model ID | - | 1 | - |
| 32000 | Bitfield16 | RO | Remote comm status | - | - | - |
| 32008 | Bitfield16 | RO | Alarm 1 | - | - | - |
| 32009 | Bitfield16 | RO | Alarm 2 | - | - | - |
| 32010 | Bitfield16 | RO | Alarm 3 | - | - | - |
| 32016 | I16 | RO | PV1 Voltage | V | 10 | /Dc/0/Voltage |
| 32017 | I16 | RO | PV1 Current | A | 100 | /Dc/0/Current |
| 32064 | I32 | RO | Input Power (DC from PV) | kW | 1000→W | /Dc/0/Power |
| 32066 | U16 | RO | Line voltage A-B | V | 10 | /Ac/L1L2/Voltage |
| 32067 | U16 | RO | Line voltage B-C | V | 10 | /Ac/L2L3/Voltage |
| 32068 | U16 | RO | Line voltage C-A | V | 10 | /Ac/L1L3/Voltage |
| 32069 | U16 | RO | Phase A voltage | V | 10 | /Ac/L1/Voltage |
| 32070 | U16 | RO | Phase B voltage | V | 10 | /Ac/L2/Voltage |
| 32071 | U16 | RO | Phase C voltage | V | 10 | /Ac/L3/Voltage |
| 32072 | I32 | RO | Phase A current | A | 1000 | /Ac/L1/Current |
| 32074 | I32 | RO | Phase B current | A | 1000 | /Ac/L2/Current |
| 32076 | I32 | RO | Phase C current | A | 1000 | /Ac/L3/Current |
| 32078 | I32 | RO | Peak active power today | kW | 1000→W | - |
| 32080 | I32 | RO | Total active power | kW | 1000→W | /Ac/Power |
| 32082 | I32 | RO | Reactive power | kVar | 1000 | - |
| 32084 | I16 | RO | Power factor | - | 1000 | - |
| 32085 | U16 | RO | Grid frequency | Hz | 100 | /Ac/Frequency |
| 32086 | U16 | RO | Efficiency | % | 100 | /Efficiency |
| 32087 | I16 | RO | Internal temperature | °C | 10 | /Temperature |
| 32088 | U16 | RO | Insulation resistance | MΩ | 1000 | - |
| 32089 | ENUM16 | RO | Device status | - | - | /StatusCode |
| 32090 | U16 | RO | Fault code | - | - | /ErrorCode |
| 32091 | EPOCHTIME | RO | Startup time | s | - | - |
| 32093 | EPOCHTIME | RO | Shutdown time | s | - | - |
| 32106 | U32 | RO | Accumulated energy yield | kWh | 100 | /Yield/Power |
| 32114 | U32 | RO | Daily energy yield | kWh | 100 | /Ac/Energy/Forward |

## Data Types

- **U16**: Unsigned 16-bit integer (1 register)
- **I16 / S16**: Signed 16-bit integer (1 register)
- **U32**: Unsigned 32-bit integer (2 registers, big-endian)
- **I32 / S32**: Signed 32-bit integer (2 registers, big-endian)
- **Bitfield16**: 16-bit bitmask – individual bits have meaning
- **ENUM16**: 16-bit enumeration – value maps to a named state
- **STR**: ASCII string (N registers = 2N bytes)
- **EPOCHTIME**: Unix timestamp in seconds (2 registers = U32)

## Byte Order

All multi-register values use **Big Endian** (most significant word first).

```
Register N:   High 16 bits
Register N+1: Low 16 bits

Example: Register 32080 = 0x0000, Register 32081 = 0x07D0
Combined: 0x000007D0 = 2000 → 2000W
```

## Scale / Gain

Victron's `register.py` uses `scale` as a **divisor**: `value = raw / scale`

Huawei documentation uses `gain` as a **multiplier**: `value = raw / gain`

These are equivalent. Examples:

| Gain (Huawei) | Scale (Victron) | Raw | Actual |
|---------------|-----------------|-----|--------|
| 1 | 1 | 2000 | 2000 W |
| 10 | 10 | 2300 | 230.0 V |
| 100 | 100 | 5000 | 50.00 Hz |
| 1000 | 1000 | 15370 | 15.370 A |

### Power Register Note (32080, 32064)

Huawei stores power in **kW with gain=1000** (raw/1000 = kW).
Since we want **Watts**: raw/1000 × 1000 = raw → scale=1

```
Raw value: 2000
Huawei doc: 2000 / 1000 = 2.0 kW
In Watts:  2000 / 1    = 2000 W  ← scale=1 in plugin
```

## Device Status Codes (Register 32089)

| Value | Hex | Description |
|-------|-----|-------------|
| 0 | 0x0000 | Standby: initialization |
| 1 | 0x0001 | Standby: insulation resistance detection |
| 2 | 0x0002 | Standby: sunlight detection |
| 3 | 0x0003 | Standby: grid detecting |
| 256 | 0x0100 | Starting |
| 512 | 0x0200 | On-grid (running normally) |
| 513 | 0x0201 | Grid connected: power limited |
| 514 | 0x0202 | Grid connected: self derating |
| 515 | 0x0203 | Off-grid operation |
| 768 | 0x0300 | OFF: unexpected shutdown |
| 769 | 0x0301 | OFF: instructed shutdown |
| 770 | 0x0302 | OFF: OVGR |
| 771 | 0x0303 | OFF: communication interrupted |
| 772 | 0x0304 | OFF: power limited |
| 773 | 0x0305 | OFF: manual startup required |
| 775 | 0x0307 | Shutdown: rapid shutdown |
| 40960 | 0xA000 | Standby: no irradiation (night) |

## Remote Communication Status (Register 32000, Bitfield16)

| Bit | Description |
|-----|-------------|
| 0 | Standby |
| 1 | Grid-connected |
| 2 | Grid-connected normally |
| 3 | Grid connection with derating (power rationing) |
| 4 | Grid connection with derating (internal causes) |
| 5 | Normal stop |
| 6 | Stop due to faults |
| 7 | Stop due to power rationing |
| 8 | Shutdown |
| 9 | Spot check |
| 10 | Off-grid operation |
| 11 | Hot Standby Operation |

⚠️ **Note**: Register 32000 is a Bitfield, NOT a simple status code.
Use register **32089** (Device Status ENUM16) for the actual operational state.

## Efficient Register Groups

Read registers in blocks to minimize bus traffic:

**Group 1 – Status (3 registers)**
```
32089: Device status (ENUM16)
32090: Fault code (U16)
```

**Group 2 – DC Input (4 registers)**
```
32016: PV1 voltage (I16)
32017: PV1 current (I16)
32064-32065: Input power (I32)
```

**Group 3 – AC Voltages (9 registers)**
```
32066: Line voltage A-B (U16)
32067: Line voltage B-C (U16)
32068: Line voltage C-A (U16)
32069: Phase A voltage (U16)
32070: Phase B voltage (U16)
32071: Phase C voltage (U16)
```

**Group 4 – AC Currents (6 registers)**
```
32072-32073: Phase A current (I32)
32074-32075: Phase B current (I32)
32076-32077: Phase C current (I32)
```

**Group 5 – AC Power & Energy (12 registers)**
```
32080-32081: Total active power (I32)
32085: Grid frequency (U16)
32086: Efficiency (U16)
32087: Internal temperature (I16)
32106-32107: Accumulated energy yield (U32)
32114-32115: Daily energy yield (U32)
```

## Troubleshooting

### No Response
1. Check baud rate: 9600
2. Check slave address: 1 (default)
3. Check RS485 wiring: A(+) and B(-) not swapped
4. Inverter powered on and not in deep standby
5. **After Huawei firmware update**: power-cycle the inverter
   (AC breaker off, wait 2 min, back on) — RS485 stack can hang

### IllegalAddress Exception
- Register not available in current inverter state (e.g. night/standby)
- Register not supported by this model
- Wrong slave address

### Register Address Formats

| Format | Example | Notes |
|--------|---------|-------|
| **Actual (used here)** | 32089 | Direct address |
| 4x format | 432090 | Add 400001 — do NOT use |
| Base-0 | 32088 | Subtract 1 — do NOT use |

Always use the actual address as listed in this document.

## Model-Specific Notes

### SUN2000-8KTL-M1 (Model ID: 428)
- All registers as documented above
- 3-phase
- Tested with Venus OS v3.67, register mapping Issue 09

### Adding Your Model
1. Read Model ID: `python3 -c "from pymodbus.client.sync import ModbusSerialClient; c = ModbusSerialClient(method='rtu', port='/dev/ttyUSB1', baudrate=9600, bytesize=8, parity='N', stopbits=1, timeout=3); c.connect(); r = c.read_holding_registers(30070, 1, unit=1); print('Model ID:', r.registers[0]); c.close()"`
2. Add to `models` dict in `huawei.py`
3. Submit a pull request!

---

*Based on SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)*
