# Changelog

All notable changes to this project are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-18

### Added

- Native macOS menu bar app (SwiftUI `MenuBarExtra`) built for macOS 27 "Golden Gate" with Swift 6 strict concurrency
- Bidirectional MIDI ↔ HUI bridge for the M-VAVE SMC-Mixer
- 8 faders (CC 30–37) mapped to Pro Tools channel volume
- Channel buttons (Note 40–47) mapped to HUI Mute 1–8
- Reserved mapping table (CC 48–96) for Solo, Record Arm, Select, Transport and Bank navigation
- Bidirectional Pro Tools feedback: fader positions, switch state → button LEDs (firmware notes 0/8/16/24 rows), audio meters
- Automatic HUI ping response (`90 00 7F`) to keep the controller alive
- Virtual MIDI ports `Avid Virtual HUI In/Out` created on launch with automatic SMC-Mixer detection and hot-plug reconnect
- Settings scene with "Open at Login" via `SMAppService`
- English and Portuguese (Brazil) localization
- Hardware preset `smc-mixer-cc.smc` decoded and documented in README

[1.0.0]: https://github.com/sbacaro/TURN/releases/tag/v1.0.0
