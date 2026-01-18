# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-01-18

### Added
- **Automated installation script** (`install.sh`) for easy setup
  - Interactive USB device identification
  - Automatic plugin installation and configuration
  - Service restart and verification
  - Colored output and progress indicators
  - Comprehensive error handling

### Fixed
- **Register 32080** (AC Total Power) - Corrected gain calculation
  - Changed from `gain=1000` (incorrect kW) to `gain=1` (correct W)
  - Now displays proper Watt values (e.g., 2500 W instead of 2.5 W)

- **Phase Power calculation** (L1/L2/L3)
  - Implemented automatic division of total power across 3 phases
  - Uses same register (32080) with `gain=3` to calculate per-phase power
  - Each phase now shows: Total Power / 3 (in Watts)

- **Register 32064** (DC Input Power) - Corrected gain calculation
  - Changed from `gain=1000` to `gain=1` for proper Watt display

- **Energy registers** (32114, 32106) - Verified correct kWh conversion
  - Maintained `gain=100` for proper kWh display
  - Daily yield and lifetime total now display correctly

### Changed
- Updated documentation to prioritize automated installation script
- Improved README.md with quick installation section
- Enhanced register documentation with accurate gain calculations

### Technical Details
- Register 32080 (I32, unit=kW in hardware):
  - Hardware stores value with gain=1000 (e.g., 2500 = 2.5 kW)
  - Plugin uses `gain=1` to read as Watt: 2500/1 = 2500 W ✓
  - Phase power uses `gain=3`: 2500/3 = 833 W per phase ✓

## [1.0.0] - 2026-01-18

### Added
- Initial release
- Full support for Huawei SUN2000-8KTL-M1 (Model ID 428)
- Modbus RTU integration via RS485
- 3-phase AC monitoring (voltage, current, power per phase)
- DC input monitoring (voltage, current, power)
- Energy tracking (daily yield and lifetime total)
- Status and error code reporting
- Automatic position detection (AC Output)
- Integration with Victron VRM portal
- Comprehensive documentation

### Tested
- Hardware: SUN2000-8KTL-M1 with Cerbo GX
- Venus OS: v3.x
- Baud rate: 9600
- Device address: 1

## [Unreleased]

---

## Version Format

- **MAJOR**: Breaking changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes, backwards compatible
