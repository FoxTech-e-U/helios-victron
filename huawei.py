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
License: MIT

Modbus Register Mapping:
-----------------------
Status:
  32000: Status Code (U16)
  32008: Error Code (U16)

AC Output:
  32080: Total AC Power (S32, 1W resolution)
  32085: Grid Frequency (U16, 0.01Hz resolution)
  32114: Daily Energy Yield (U32, 0.01kWh resolution)
  32106: Accumulated Energy Yield (U32, 0.01kWh resolution)

AC Phases (L1=32069-32072, L2=32070-32074, L3=32071-32076):
  32069/70/71: Phase Voltage (U16, 0.1V resolution)
  32072/74/76: Phase Current (S32, 0.001A resolution)
  32064/66/68: Phase Power (S32, 1W resolution)

DC Input:
  32064: DC Power (S32, 1W resolution)
  32016: DC Voltage (U16, 0.1V resolution)
  32017: DC Current (S16, 0.01A resolution)

D-Bus Paths:
-----------
/Ac/Power                - Total AC output power (W)
/Ac/Energy/Forward       - Daily energy production (kWh)
/Yield/Power             - Lifetime total energy (kWh)
/Ac/Frequency            - Grid frequency (Hz)
/Ac/L1/Voltage           - L1 voltage (V)
/Ac/L1/Current           - L1 current (A)
/Ac/L1/Power             - L1 power (W)
(... L2 and L3 similar)
/Dc/0/Voltage            - DC input voltage (V)
/Dc/0/Current            - DC input current (A)
/Dc/0/Power              - DC input power (W)
/Position                - Inverter position (1 = AC Output)
/StatusCode              - Inverter status
/ErrorCode               - Error/fault code
"""

import device
import probe
from register import *


class Huawei_PV_Inverter(device.EnergyMeter):
    """
    Huawei SUN2000 PV Inverter integration.
    
    Inherits from device.EnergyMeter to get automatic Position setting
    and proper PV inverter behavior in the Victron system.
    """
    
    vendor_id = 'huawei'
    vendor_name = 'Huawei'
    productid = 0xB042  # Product ID for Huawei SUN2000
    productname = 'Huawei SUN2000'
    min_timeout = 0.5
    default_role = 'pvinverter'
    default_instance = 20
    allowed_roles = ['pvinverter']
    nr_phases = 3
    position = None  # Will be set automatically by EnergyMeter base class
    
    def __init__(self, *args):
        super().__init__(*args)
        
        # No info registers needed (Serial, FirmwareVersion, etc.)
        # These would require Reg_text which can cause null byte issues
        self.info_regs = []
        
        # Data registers - polled continuously
        self.data_regs = [
            # Status Registers
            Reg_u16(32000, '/StatusCode'),
            Reg_u16(32008, '/ErrorCode'),
            
            # AC Output - Total
            Reg_s32b(32080, '/Ac/Power', 1, '%.0f W'),
            Reg_u32b(32114, '/Ac/Energy/Forward', 100, '%.2f kWh'),  # Daily yield
            Reg_u32b(32106, '/Yield/Power', 100, '%.2f kWh'),        # Lifetime total
            
            # AC Output - Frequency (same for all phases)
            Reg_u16(32085, '/Ac/Frequency', 100, '%.2f Hz'),
            
            # AC Output - Phase 1
            Reg_u16(32069, '/Ac/L1/Voltage', 10, '%.1f V'),
            Reg_s32b(32072, '/Ac/L1/Current', 1000, '%.3f A'),
            Reg_s32b(32064, '/Ac/L1/Power', 1, '%.0f W'),
            
            # AC Output - Phase 2
            Reg_u16(32070, '/Ac/L2/Voltage', 10, '%.1f V'),
            Reg_s32b(32074, '/Ac/L2/Current', 1000, '%.3f A'),
            Reg_s32b(32066, '/Ac/L2/Power', 1, '%.0f W'),
            
            # AC Output - Phase 3
            Reg_u16(32071, '/Ac/L3/Voltage', 10, '%.1f V'),
            Reg_s32b(32076, '/Ac/L3/Current', 1000, '%.3f A'),
            Reg_s32b(32068, '/Ac/L3/Power', 1, '%.0f W'),
            
            # DC Input (from solar panels)
            Reg_s32b(32064, '/Dc/0/Power', 1, '%.0f W'),
            Reg_u16(32016, '/Dc/0/Voltage', 10, '%.1f V'),
            Reg_s16(32017, '/Dc/0/Current', 100, '%.2f A'),
        ]
    
    def get_ident(self):
        """Return unique identifier for this device."""
        return 'huawei_sun2000'


# Supported inverter models
# Add your model here if different from SUN2000-8KTL-M1
models = {
    428: {
        'model': 'SUN2000-8KTL-M1',
        'handler': Huawei_PV_Inverter,
    },
    # Add more models here:
    # XXX: {
    #     'model': 'SUN2000-XXKTL-XX',
    #     'handler': Huawei_PV_Inverter,
    # },
}

# Register probe handler
# This tells the modbus-client how to detect Huawei inverters
probe.add_handler(probe.ModelRegister(
    Reg_u16(30070),  # Model ID register
    models,
    methods=['rtu'],  # Modbus RTU only (not TCP)
    rates=[9600],     # Baud rate
    units=[1, 2, 3]   # Modbus device addresses to try
))
