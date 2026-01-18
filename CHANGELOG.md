# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
