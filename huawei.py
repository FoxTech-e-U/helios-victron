"""
Huawei SUN2000 Modbus RTU Integration for Victron Venus OS
===========================================================

Plugin for dbus-modbus-client to integrate Huawei SUN2000 series inverters
via Modbus RTU (RS485) into Victron Energy GX devices.

Tested with: SUN2000-8KTL-M1 (Model ID: 428)
Protocol: Modbus RTU
Baud Rate: 9600
Device Address: 1 (default)

Author: Olli from FoxTech e.U.
Repository: https://github.com/FoxTech-e-U/helios-victron
License: GPL-3.0

Modbus Register Mapping (SUN2000MA Modbus Interface Definitions, Issue 09, 2025-12-19):
---------------------------------------------------------------------------------------

Equipment Info:
  30000: Model             (STR, 15 registers)
  30070: Model ID          (U16)

Status:
  32000: Remote comm status (Bitfield16) - Bit0=standby, Bit1=grid-connected, Bit6=fault, etc.
  32002: Running status     (Bitfield16) - Bit0=locked, Bit1=PV connected, Bit2=DSP collecting
  32008: Alarm 1            (Bitfield16)
  32009: Alarm 2            (Bitfield16)
  32010: Alarm 3            (Bitfield16)
  32089: Device status      (ENUM16)    - 0x0200=On-grid running, 0x0300=fault, etc.
  32090: Fault code         (U16)

AC Output - Total:
  32078: Peak active power today  (I32, kW, scale=1000 -> W)
  32080: Active power             (I32, kW, scale=1000 -> W)
  32082: Reactive power           (I32, kVar, scale=1000)
  32084: Power factor             (I16, scale=1000)
  32085: Grid frequency           (U16, Hz, scale=100)
  32086: Efficiency               (U16, %, scale=100)
  32087: Internal temperature     (I16, °C, scale=10)
  32106: Accumulated energy yield (U32, kWh, scale=100)
  32114: Daily energy yield       (U32, kWh, scale=100)

AC Output - Phases (L1/L2/L3):
  32066: Line voltage A-B  (U16, V, scale=10)
  32067: Line voltage B-C  (U16, V, scale=10)
  32068: Line voltage C-A  (U16, V, scale=10)
  32069: Phase A voltage   (U16, V, scale=10)
  32070: Phase B voltage   (U16, V, scale=10)
  32071: Phase C voltage   (U16, V, scale=10)
  32072: Phase A current   (I32, A, scale=1000)
  32074: Phase B current   (I32, A, scale=1000)
  32076: Phase C current   (I32, A, scale=1000)

DC Input:
  32016: PV1 voltage  (I16, V, scale=10)
  32017: PV1 current  (I16, A, scale=100)
  32064: Input power  (I32, kW, scale=1000 -> W)

D-Bus Paths:
-----------
/Ac/Power                - Total AC output power (W)
/Ac/Energy/Forward       - Daily energy production (kWh)
/Yield/Power             - Lifetime total energy (kWh)
/Ac/Frequency            - Grid frequency (Hz)
/Ac/L1/Voltage           - L1 phase voltage (V)
/Ac/L1/Current           - L1 current (A)
/Ac/L1/Power             - L1 power (W, estimated as Total/3)
/Ac/L2/Voltage           - L2 phase voltage (V)
/Ac/L2/Current           - L2 current (A)
/Ac/L2/Power             - L2 power (W, estimated as Total/3)
/Ac/L3/Voltage           - L3 phase voltage (V)
/Ac/L3/Current           - L3 current (A)
/Ac/L3/Power             - L3 power (W, estimated as Total/3)
/Dc/0/Voltage            - PV1 input voltage (V)
/Dc/0/Current            - PV1 input current (A)
/Dc/0/Power              - PV input power (W)
/StatusCode              - Device status (ENUM16 from register 32089)
/ErrorCode               - Fault code (U16 from register 32090)
/Ac/L1-L2/Voltage        - Line voltage A-B (V)
/Ac/L2-L3/Voltage        - Line voltage B-C (V)
/Ac/L1-L3/Voltage        - Line voltage C-A (V)
/Temperature             - Internal temperature (°C)
/Efficiency              - Inverter efficiency (%)
"""

import device
import probe
from register import *


class Huawei_PV_Inverter(device.EnergyMeter):
    """
    Huawei SUN2000 PV Inverter integration.

    Register mapping based on:
    SUN2000MA Modbus Interface Definitions, Issue 09 (2025-12-19)
    """

    vendor_id = 'huawei'
    vendor_name = 'Huawei'
    productid = 0xB042
    productname = 'Huawei SUN2000'
    min_timeout = 1.0
    default_role = 'pvinverter'
    default_instance = 20
    allowed_roles = ['pvinverter']
    nr_phases = 3
    position = None

    def __init__(self, *args):
        super().__init__(*args)

        self.info_regs = []

        self.data_regs = [
            # --- Status ---
            # Device status ENUM16: 0x0200=On-grid running, 0x0300=fault shutdown, etc.
            Reg_u16(32089, '/StatusCode'),
            # Fault code
            Reg_u16(32090, '/ErrorCode'),

            # --- AC Output - Total ---
            # Active power: I32, unit kW, gain 1000 in doc → raw/1000=kW → raw/1=W
            Reg_s32b(32080, '/Ac/Power', 1, '%.0f W'),
            # Daily energy yield: U32, kWh, gain 100 → raw/100=kWh
            Reg_u32b(32114, '/Ac/Energy/Forward', 100, '%.2f kWh'),
            # Accumulated energy yield: U32, kWh, gain 100 → raw/100=kWh
            Reg_u32b(32106, '/Yield/Power', 100, '%.2f kWh'),
            # Grid frequency: U16, Hz, gain 100 → raw/100=Hz
            Reg_u16(32085, '/Ac/Frequency', 100, '%.2f Hz'),
            # Internal temperature: I16, °C, gain 10 → raw/10=°C
            Reg_s16(32087, '/Temperature', 10, '%.1f °C'),
            # Efficiency: U16, %, gain 100 → raw/100=%
            Reg_u16(32086, '/Efficiency', 100, '%.2f %%'),

            # --- AC Output - Phase voltages ---
            # Phase voltages: U16, V, gain 10 → raw/10=V
            Reg_u16(32069, '/Ac/L1/Voltage', 10, '%.1f V'),
            Reg_u16(32070, '/Ac/L2/Voltage', 10, '%.1f V'),
            Reg_u16(32071, '/Ac/L3/Voltage', 10, '%.1f V'),

            # Line voltages: U16, V, gain 10 → raw/10=V
            Reg_u16(32066, '/Ac/L1L2/Voltage', 10, '%.1f V'),
            Reg_u16(32067, '/Ac/L2L3/Voltage', 10, '%.1f V'),
            Reg_u16(32068, '/Ac/L1L3/Voltage', 10, '%.1f V'),

            # --- AC Output - Phase currents ---
            # Phase currents: I32, A, gain 1000 → raw/1000=A
            Reg_s32b(32072, '/Ac/L1/Current', 1000, '%.3f A'),
            Reg_s32b(32074, '/Ac/L2/Current', 1000, '%.3f A'),
            Reg_s32b(32076, '/Ac/L3/Current', 1000, '%.3f A'),

            # --- AC Output - Per-phase power (estimated as Total/3) ---
            # No dedicated per-phase power registers in SUN2000MA spec
            # Using total power register with scale*3 as approximation
            Reg_s32b(32080, '/Ac/L1/Power', 3, '%.0f W'),
            Reg_s32b(32080, '/Ac/L2/Power', 3, '%.0f W'),
            Reg_s32b(32080, '/Ac/L3/Power', 3, '%.0f W'),

            # --- DC Input ---
            # Input power: I32, kW, gain 1000 → raw/1000=kW → raw/1=W
            Reg_s32b(32064, '/Dc/0/Power', 1, '%.0f W'),
            # PV1 voltage: I16, V, gain 10 → raw/10=V
            Reg_u16(32016, '/Dc/0/Voltage', 10, '%.1f V'),
            # PV1 current: I16, A, gain 100 → raw/100=A
            Reg_s16(32017, '/Dc/0/Current', 100, '%.2f A'),
        ]

    def get_ident(self):
        return 'huawei_sun2000'


# ---------------------------------------------------------------------------
# Supported inverter models
# Model ID from register 30070
# Add your model here if not listed
# ---------------------------------------------------------------------------
models = {
    428: {
        'model': 'SUN2000-8KTL-M1',
        'handler': Huawei_PV_Inverter,
    },
    # Common SUN2000-M0/M1/M2 series - add as confirmed:
    # 424: {'model': 'SUN2000-4KTL-M1',  'handler': Huawei_PV_Inverter},
    # 425: {'model': 'SUN2000-5KTL-M1',  'handler': Huawei_PV_Inverter},
    # 426: {'model': 'SUN2000-6KTL-M1',  'handler': Huawei_PV_Inverter},
    # 427: {'model': 'SUN2000-7KTL-M1',  'handler': Huawei_PV_Inverter},
    # 429: {'model': 'SUN2000-10KTL-M1', 'handler': Huawei_PV_Inverter},
    # 430: {'model': 'SUN2000-12KTL-M1', 'handler': Huawei_PV_Inverter},
    # 431: {'model': 'SUN2000-15KTL-M1', 'handler': Huawei_PV_Inverter},
    # 432: {'model': 'SUN2000-17KTL-M1', 'handler': Huawei_PV_Inverter},
    # 433: {'model': 'SUN2000-20KTL-M2', 'handler': Huawei_PV_Inverter},
}

# ---------------------------------------------------------------------------
# Probe handler
# Detects Huawei inverters by reading Model ID from register 30070
# ---------------------------------------------------------------------------
probe.add_handler(probe.ModelRegister(
    Reg_u16(30070),
    models,
    methods=['rtu'],
    rates=[9600],
    units=[1],
))
