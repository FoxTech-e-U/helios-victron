# Modbus Register Reference

Complete Modbus register mapping for Huawei SUN2000 inverters.

Based on: **Huawei SUN2000 Solar Inverter Modbus Interface Definitions**

## Register Overview

| Address | Type | R/W | Description | Unit | Gain | D-Bus Path |
|---------|------|-----|-------------|------|------|------------|
| 30070 | U16 | RO | Model ID | - | 1 | - |
| 32000 | U16 | RO | Status Code | - | 1 | /StatusCode |
| 32008 | U16 | RO | Error Code | - | 1 | /ErrorCode |
| 32016 | U16 | RO | DC Voltage | V | 10 | /Dc/0/Voltage |
| 32017 | S16 | RO | DC Current | A | 100 | /Dc/0/Current |
| 32064 | S32 | RO | DC Power / L1 Power | W | 1 | /Dc/0/Power, /Ac/L1/Power |
| 32066 | S32 | RO | L2 Power | W | 1 | /Ac/L2/Power |
| 32068 | S32 | RO | L3 Power | W | 1 | /Ac/L3/Power |
| 32069 | U16 | RO | L1 Voltage | V | 10 | /Ac/L1/Voltage |
| 32070 | U16 | RO | L2 Voltage | V | 10 | /Ac/L2/Voltage |
| 32071 | U16 | RO | L3 Voltage | V | 10 | /Ac/L3/Voltage |
| 32072 | S32 | RO | L1 Current | A | 1000 | /Ac/L1/Current |
| 32074 | S32 | RO | L2 Current | A | 1000 | /Ac/L2/Current |
| 32076 | S32 | RO | L3 Current | A | 1000 | /Ac/L3/Current |
| 32080 | S32 | RO | Total AC Power | W | 1 | /Ac/Power |
| 32085 | U16 | RO | Grid Frequency | Hz | 100 | /Ac/Frequency |
| 32106 | U32 | RO | Accumulated Energy Yield | kWh | 100 | /Yield/Power |
| 32114 | U32 | RO | Daily Energy Yield | kWh | 100 | /Ac/Energy/Forward |

## Data Types

- **U16**: Unsigned 16-bit integer (0 to 65535)
- **S16**: Signed 16-bit integer (-32768 to 32767)
- **U32**: Unsigned 32-bit integer (0 to 4294967295)
- **S32**: Signed 32-bit integer (-2147483648 to 2147483647)

## Byte Order

All multi-byte values use **Big Endian** (most significant byte first).

For 32-bit registers:
- **S32b** / **U32b** = Big Endian, High word first
- Register N = High 16 bits
- Register N+1 = Low 16 bits

Example for register 32080 (Total AC Power):
```
Register 32080: 0x0000  (High word)
Register 32081: 0x1F40  (Low word)
Combined: 0x00001F40 = 8000W
```

## Gain/Scaling

Values must be divided by the gain factor to get actual values:

| Gain | Precision | Example Raw | Example Actual |
|------|-----------|-------------|----------------|
| 1 | 1 | 8000 | 8000 W |
| 10 | 0.1 | 2300 | 230.0 V |
| 100 | 0.01 | 2157 | 21.57 A |
| 1000 | 0.001 | 8750 | 8.750 A |

## Status Codes

| Code | Hex | Status | Description |
|------|-----|--------|-------------|
| 0 | 0x0000 | Standby | Waiting (no irradiation) |
| 1 | 0x0001 | Grid-connected | Normal operation |
| 2 | 0x0002 | Grid-connected (derating) | Power limitation active |
| 3 | 0x0003 | Shutdown | Normal shutdown |
| 4 | 0x0004 | Fault | Fault condition |
| 5 | 0x0005 | Off-grid charging | Battery charging mode |

Common status codes during operation:
- **Morning startup**: 0 → 1
- **Normal day**: 1
- **Clouds**: 1 or 2
- **Evening shutdown**: 1 → 3 → 0
- **Night**: 0

## Error Codes

Error codes are specific to your inverter model. Refer to Huawei documentation for meanings.

Common error codes:
- **0**: No error
- **1xxx**: Grid faults
- **2xxx**: DC input faults
- **3xxx**: AC output faults
- **4xxx**: Temperature faults
- **5xxx**: Communication faults

## Register Read Examples

### Python (pymodbus)

```python
from pymodbus.client import ModbusSerialClient

client = ModbusSerialClient(
    port='/dev/ttyUSB1',
    baudrate=9600,
    parity='N',
    stopbits=1,
    bytesize=8,
    timeout=1
)

if client.connect():
    # Read status code (U16)
    result = client.read_holding_registers(32000, 1, slave=1)
    status = result.registers[0]
    print(f"Status: {status}")
    
    # Read total power (S32)
    result = client.read_holding_registers(32080, 2, slave=1)
    power_raw = (result.registers[0] << 16) | result.registers[1]
    power = power_raw / 1  # Gain = 1
    print(f"Power: {power}W")
    
    # Read L1 voltage (U16)
    result = client.read_holding_registers(32069, 1, slave=1)
    voltage = result.registers[0] / 10  # Gain = 10
    print(f"L1 Voltage: {voltage}V")
    
    client.close()
```

### Bash (modbus CLI)

```bash
# Read status code (register 32000, 1 register, slave 1)
modbus read -s 1 -a 32000 -c 1 -t 4 -b 9600 -d 8 -p none /dev/ttyUSB1

# Read total power (register 32080, 2 registers for S32)
modbus read -s 1 -a 32080 -c 2 -t 4 -b 9600 -d 8 -p none /dev/ttyUSB1
```

## Register Groups for Optimization

For efficient polling, read registers in groups:

**Group 1: Status (2 registers)**
- 32000-32001: Status Code, Error Code

**Group 2: DC Input (4 registers)**
- 32016-32019: DC Voltage, DC Current, DC Power (2 regs)

**Group 3: AC Output (10 registers)**
- 32064-32073: Phase Powers (L1, L2, L3) + Voltages

**Group 4: AC Currents (6 registers)**
- 32072-32077: Phase Currents (L1, L2, L3)

**Group 5: Energy (6 registers)**
- 32080-32085: Total Power, Frequency
- 32106-32107: Accumulated Energy
- 32114-32115: Daily Energy

## Timing Considerations

- **Minimum request interval**: 500ms (min_timeout = 0.5)
- **Typical update rate**: 1-3 seconds
- **Energy counters update**: Every minute
- **Daily energy reset**: Midnight local time

## Troubleshooting Register Reads

### No Response

Check:
1. Correct baud rate (9600)
2. Correct slave address (default 1)
3. Inverter is powered on
4. RS485 wiring (A/B not swapped)

### Invalid Data

Check:
1. Byte order (should be big endian)
2. Register address (some docs use 4xxxx, subtract 40001)
3. Gain factor applied correctly
4. Signed vs unsigned interpretation

### Register Address Confusion

Some Modbus documentation uses different address formats:

| Format | Address | Notes |
|--------|---------|-------|
| **Actual** | 32000 | What we use |
| **4x Format** | 432001 | Add 400001 |
| **Base-0** | 31999 | Subtract 1 |

Always use the "Actual" address format (32000, not 432001).

## Additional Resources

- [Huawei FusionSolar Documentation](https://akkudoktor.net/uploads/short-url/gAxRsmNJqWHuTzQKCz7GXAYmhoY.pdf)

## Model-Specific Differences

### SUN2000-8KTL-M1 (Model ID 428)
- All registers as documented above
- 3-phase only
- Max DC voltage: 1100V
- Rated power: 8000W

### Other Models

If you have a different SUN2000 model:
1. Check the model ID at register 30070
2. Verify register addresses in your inverter's manual
3. Add the model to `huawei.py` models dictionary
4. Test and report compatibility!

## Contributing Register Information

If you have a different SUN2000 model, please contribute:
1. Report model ID (register 30070)
2. Confirm working register addresses
3. Note any differences from this documentation
4. Submit PR or issue on GitHub

---

**Note**: This documentation is based on SUN2000-8KTL-M1. Other models may have different register layouts.
