#!/usr/bin/env python3
"""
Helios Huawei SUN2000 TCP Daemon
==================================

Publishes Huawei SUN2000 inverter data to Victron D-Bus via Modbus TCP
(through the Huawei SDongle), independent of dbus-modbus-client.

Why TCP instead of RTU:
  The Huawei RS485 stack frequently hangs after Cerbo reboots or Huawei
  firmware updates, requiring inverter power-cycles to recover. Modbus TCP
  via the SDongle has proven more stable in testing. RS485 and the SDongle
  cannot be used simultaneously, so this daemon replaces the RTU connection
  for the Huawei entirely (ABB Terra keeps using RTU on ttyUSB1).

  The SDongle only allows a few consecutive requests per TCP connection
  before closing it, so this daemon opens a fresh connection for every
  register block it reads.

This daemon registers its own D-Bus service (com.victronenergy.pvinverter.
huawei_sun2000) using Victron's VeDbusService, replacing the RTU-based
huawei.py plugin for dbus-modbus-client entirely - do not run both at once.

Author: FoxTech e.U.
Repository: https://github.com/FoxTech-e-U/helios-victron
License: GPL-3.0
"""

import sys
import os
import time
import logging
import signal
import threading
from pymodbus.client.sync import ModbusTcpClient

sys.path.insert(0, '/opt/victronenergy/dbus-modbus-client')
sys.path.insert(0, '/opt/victronenergy/velib_python')

from vedbus import VeDbusService
import dbus
import dbus.mainloop.glib
from gi.repository import GLib

# =============================================================================
# Configuration
# =============================================================================
DONGLE_IP        = '172.20.0.186'
DONGLE_PORT      = 502
MODBUS_UNIT      = 1

POLL_INTERVAL    = 10        # seconds between full poll cycles
CONNECT_TIMEOUT  = 2         # seconds (local network TCP - fast fail if no response)
INTER_READ_DELAY = 0.3       # seconds between register block reads

DEVICE_INSTANCE  = 20

LOG_LEVEL        = logging.INFO

log = logging.getLogger(__name__)


def setup_logging():
    logging.basicConfig(
        level=LOG_LEVEL,
        format='%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
        handlers=[logging.StreamHandler(sys.stdout)]
    )


def read_block(ip, port, start, count, unit=MODBUS_UNIT, timeout=CONNECT_TIMEOUT):
    """Open a fresh TCP connection, read one block, close. Returns registers or None."""
    log.debug(f"read_block: connecting for reg {start}...")
    client = ModbusTcpClient(ip, port=port, timeout=timeout)
    try:
        if not client.connect():
            log.debug(f"read_block: connect() failed for reg {start}")
            return None
        log.debug(f"read_block: connected, reading reg {start}")
        time.sleep(0.1)
        r = client.read_holding_registers(start, count, unit=unit)
        log.debug(f"read_block: read done for reg {start}")
        if hasattr(r, 'registers'):
            return r.registers
        return None
    except Exception as e:
        log.debug(f"read_block {start}/{count}: {e}")
        return None
    finally:
        try:
            client.close()
        except Exception:
            pass
        log.debug(f"read_block: closed for reg {start}")


def u32(regs, idx, signed=False):
    val = (regs[idx] << 16) | regs[idx + 1]
    if signed and val > 0x7FFFFFFF:
        val -= 0x100000000
    return val


def i16(val):
    if val > 0x7FFF:
        val -= 0x10000
    return val


class HuaweiTcpDaemon:
    def __init__(self):
        self.running = True
        signal.signal(signal.SIGTERM, self._shutdown)
        signal.signal(signal.SIGINT, self._shutdown)

        self.service = self._create_service()
        self.mainloop = GLib.MainLoop()

    def _shutdown(self, *_):
        log.info("Shutdown signal received")
        self.running = False
        self.mainloop.quit()

    def _create_service(self):
        svc = VeDbusService('com.victronenergy.pvinverter.huawei_sun2000', register=False)

        svc.add_path('/Mgmt/ProcessName', __file__)
        svc.add_path('/Mgmt/ProcessVersion', '2.0.1-tcp')
        svc.add_path('/Mgmt/Connection', f'Modbus TCP {DONGLE_IP}:{DONGLE_PORT}')
        svc.add_path('/DeviceInstance', DEVICE_INSTANCE)
        svc.add_path('/ProductId', 0xB042)
        svc.add_path('/ProductName', 'Huawei SUN2000')
        svc.add_path('/Model', 'SUN2000-8KTL-M1')
        svc.add_path('/Connected', 0)
        svc.add_path('/AllowedRoles', ['pvinverter'])
        svc.add_path('/Role', 'pvinverter')
        svc.add_path('/Position', 1)
        svc.add_path('/NrOfPhases', 3)
        svc.add_path('/Serial', 'tcp-dongle')

        # Data paths
        svc.add_path('/StatusCode', None)
        svc.add_path('/ErrorCode', None)
        svc.add_path('/Ac/Power', None, gettextcallback=lambda p, v: f"{v:.0f} W" if v is not None else None)
        svc.add_path('/Ac/L1/Power', None)
        svc.add_path('/Ac/L2/Power', None)
        svc.add_path('/Ac/L3/Power', None)
        svc.add_path('/Ac/Energy/Forward', None, gettextcallback=lambda p, v: f"{v:.2f} kWh" if v is not None else None)
        svc.add_path('/Yield/Power', None, gettextcallback=lambda p, v: f"{v:.2f} kWh" if v is not None else None)
        svc.add_path('/Ac/Frequency', None, gettextcallback=lambda p, v: f"{v:.2f} Hz" if v is not None else None)
        svc.add_path('/Efficiency', None, gettextcallback=lambda p, v: f"{v:.2f} %" if v is not None else None)
        svc.add_path('/Temperature', None, gettextcallback=lambda p, v: f"{v:.1f} °C" if v is not None else None)
        svc.add_path('/Ac/L1/Voltage', None)
        svc.add_path('/Ac/L2/Voltage', None)
        svc.add_path('/Ac/L3/Voltage', None)
        svc.add_path('/Ac/L1/Current', None)
        svc.add_path('/Ac/L2/Current', None)
        svc.add_path('/Ac/L3/Current', None)
        svc.add_path('/Dc/0/Power', None)
        svc.add_path('/Dc/0/Voltage', None)
        svc.add_path('/Dc/0/Current', None)

        svc.register()
        log.info("D-Bus service registered: com.victronenergy.pvinverter.huawei_sun2000")
        return svc

    def poll_once(self):
        """One full poll cycle. Each register group gets its own TCP connection."""
        svc = self.service
        ok_count = 0
        total = 0

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32089, 1)
        if regs:
            svc['/StatusCode'] = regs[0]
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32090, 1)
        if regs:
            svc['/ErrorCode'] = regs[0]
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32080, 2)
        if regs:
            power_w = u32(regs, 0, signed=True)
            svc['/Ac/Power'] = power_w
            svc['/Ac/L1/Power'] = round(power_w / 3)
            svc['/Ac/L2/Power'] = round(power_w / 3)
            svc['/Ac/L3/Power'] = round(power_w / 3)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32106, 2)
        if regs:
            svc['/Yield/Power'] = round(u32(regs, 0) / 100, 2)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32114, 2)
        if regs:
            svc['/Ac/Energy/Forward'] = round(u32(regs, 0) / 100, 2)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32085, 1)
        if regs:
            svc['/Ac/Frequency'] = round(regs[0] / 100, 2)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32086, 1)
        if regs:
            svc['/Efficiency'] = round(regs[0] / 100, 2)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32087, 1)
        if regs:
            svc['/Temperature'] = round(i16(regs[0]) / 10, 1)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32069, 3)
        if regs:
            svc['/Ac/L1/Voltage'] = round(regs[0] / 10, 1)
            svc['/Ac/L2/Voltage'] = round(regs[1] / 10, 1)
            svc['/Ac/L3/Voltage'] = round(regs[2] / 10, 1)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32072, 2)
        if regs:
            svc['/Ac/L1/Current'] = round(u32(regs, 0, signed=True) / 1000, 3)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32074, 2)
        if regs:
            svc['/Ac/L2/Current'] = round(u32(regs, 0, signed=True) / 1000, 3)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32076, 2)
        if regs:
            svc['/Ac/L3/Current'] = round(u32(regs, 0, signed=True) / 1000, 3)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32064, 2)
        if regs:
            svc['/Dc/0/Power'] = u32(regs, 0, signed=True)
            ok_count += 1
        time.sleep(INTER_READ_DELAY)

        total += 1
        regs = read_block(DONGLE_IP, DONGLE_PORT, 32016, 2)
        if regs:
            svc['/Dc/0/Voltage'] = round(regs[0] / 10, 1)
            svc['/Dc/0/Current'] = round(i16(regs[1]) / 100, 2)
            ok_count += 1

        svc['/Connected'] = 1 if ok_count > 0 else 0
        return ok_count, total

    def poll_loop(self):
        """Runs in a background thread. GLib mainloop stays free for D-Bus/signals."""
        log.info("Poll thread started")
        while self.running:
            start = time.time()
            try:
                ok, total = self.poll_once()
                elapsed = time.time() - start
                log.info(f"Poll cycle: {ok}/{total} registers OK ({elapsed:.1f}s)")
            except Exception as e:
                log.error(f"Poll cycle error: {e}", exc_info=True)
                elapsed = time.time() - start

            remaining = POLL_INTERVAL - elapsed
            # Sleep in small steps so shutdown is responsive
            while remaining > 0 and self.running:
                step = min(0.5, remaining)
                time.sleep(step)
                remaining -= step

    def run(self):
        log.info("=" * 60)
        log.info("Helios Huawei SUN2000 TCP Daemon starting")
        log.info(f"  Dongle:        {DONGLE_IP}:{DONGLE_PORT}")
        log.info(f"  Poll interval: {POLL_INTERVAL}s")
        log.info("=" * 60)

        poll_thread = threading.Thread(target=self.poll_loop, daemon=True)
        log.info(f"Starting poll thread (daemon={poll_thread.daemon})...")
        poll_thread.start()
        log.info(f"Poll thread alive: {poll_thread.is_alive()}")

        self.mainloop.run()
        log.info("Daemon stopped")


if __name__ == '__main__':
    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    setup_logging()
    daemon = HuaweiTcpDaemon()
    daemon.run()
