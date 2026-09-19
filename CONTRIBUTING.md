# Contributing to TURN

Thank you for considering a contribution! This project follows the [PolyForm Noncommercial License 1.0.0](LICENSE) — by submitting a contribution, you agree it will be licensed under the same terms.

## Getting started

1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-feature
   ```
2. Open `TURN.xcodeproj` in Xcode 18+ (macOS 27 SDK required).
3. Make your changes and verify both builds pass:
   ```bash
   xcodebuild -project TURN.xcodeproj -scheme TURN -configuration Debug build
   xcodebuild -project TURN.xcodeproj -scheme TURN -configuration Release build
   ```

## Code guidelines

- **Swift 6 strict concurrency** — no new warnings; new types should be `Sendable` where possible
- **HIG first** — UI changes must follow Apple's Human Interface Guidelines for macOS 27 (native SF Symbols, `MenuBarExtra`, Settings scene, semantic colors)
- **No `print`** — use the project's `Logger` instances (`subsystem: com.samuelbacaro.TURN`)
- **Localization** — all user-facing strings go through `String(localized:)` and exist in both `en` and `pt-BR` in `Localizable.xcstrings`
- **No manual pbxproj edits** — the project uses `PBXFileSystemSynchronizedRootGroup`; add files to the `TURN/` folder and Xcode picks them up

## Mapping changes

The MIDI mapping table is the contract between the app and the decoded hardware preset (`smc-mixer-cc.smc`). If you change `DefaultMappings.json`:

1. Keep `FADER_1..8` on CC 30–37 and channel buttons on Note 40–47 (hardware constraint)
2. Document any new reserved CC ranges in the README table
3. Re-verify LED feedback row notes (0/8/16/24 rows) if switching logic changes

## Reporting bugs

Open an [issue](https://github.com/sbacaro/TURN/issues) with:

- macOS and Pro Tools versions
- SMC-Mixer firmware/mode (CC Mode expected)
- Console.app output filtered by subsystem `com.samuelbacaro.TURN`
- Steps to reproduce

## Pull requests

- Keep PRs focused; one feature or fix per PR
- Describe what changed and why
- Confirm both build configurations pass before submitting

Thank you for helping make TURN better!
