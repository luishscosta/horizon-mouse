# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org/).

## [Unreleased]

## [0.3.4] - 2026-11-09

### Changed
- Shortcut action: one editor with **Record shortcut** and a modifier/key picker (recording and picking no longer overlap). While capture is on, recording goes through the event tap, so system shortcuts such as ⌃→ and ⌘Space can be recorded.

### Fixed
- Shortcuts such as ⌃→ and ⌘Space did nothing when fired from a mouse button: keys are now posted at the HID level with the modifier presses and the arrow flags a real keyboard sends.

## [0.3.3] - 2026-11-09

### Fixed
- Hold gestures and Mission Control clicks: the lost-release check read the button as released while it was still pressed (swallowed presses never reach the HID state), so every press ended after 0.1 s. The check is removed; a missed release is still recovered on the next press.

## [0.3.2] - 2026-11-06

### Changed
- Smoothness now has its own section (it applies to vertical and horizontal scrolling).

### Fixed
- The window header no longer shifts the tabs when the subtitle changes.

## [0.3.1] - 2026-11-06

### Added
- Scroll **Acceleration** (off by default): fast wheel spins travel farther, up to 4x, so scrolling can now exceed the system speed. A lone notch is unchanged.
- Scroll **Smoothness** slider for the glide length (default matches the previous behavior).

## [0.3.0] - 2026-11-06

### Added
- Translations: French, German, Italian, Japanese, Korean, Simplified Chinese, Russian and Turkish (community review welcome).

## [0.2.1] - 2026-11-06

### Fixed
- Removed an outdated notice saying every new version needs Accessibility to be granted again.

## [0.2.0] - 2026-11-06

### Changed
- Renamed to **Horizon Mouse** (previously Mac Mouse Desk). New bundle identifier `io.github.luishscosta.horizonmouse`: Accessibility must be granted once more. Settings are migrated automatically.
- Homebrew: `brew install luishscosta/tap/horizon-mouse` (the old cask name migrates).

## [0.1.7] - 2026-11-06

### Added
- Universal binary (Apple Silicon and Intel).
- Tested hardware table in the README.

## [0.1.6] - 2026-11-06

### Changed
- Project language is now English; Portuguese and Spanish are translations.
- Permission prompt text follows the system language.
- Releases attach `SHA256SUMS.txt`.

## [0.1.5] - 2026-11-06

### Added
- Support for mouse buttons that send a keyboard shortcut (requires Input Monitoring).
- **Identify button** can bind an unrecognized button to the selected control.

### Changed
- Rewrote the desktop-switch gesture and wheel smoothing code.

## [0.1.4]
- Purple app icon.

## [0.1.3]
- Releases signed with a stable certificate so the Accessibility grant survives updates; DMG added.

## [0.1.2]
- Version shown in the app and menu.

## [0.1.1]
- App icon; fixed the Hold gesture.

## [0.1.0]
- First release: button gestures, desktop switching, smooth scrolling.

[Unreleased]: https://github.com/luishscosta/horizon-mouse/compare/v0.2.1...HEAD
[0.2.1]: https://github.com/luishscosta/horizon-mouse/releases/tag/v0.2.1
[0.2.0]: https://github.com/luishscosta/horizon-mouse/releases/tag/v0.2.0
[0.1.7]: https://github.com/luishscosta/horizon-mouse/releases/tag/v0.1.7
[0.1.6]: https://github.com/luishscosta/horizon-mouse/releases/tag/v0.1.6
[0.1.5]: https://github.com/luishscosta/horizon-mouse/releases/tag/v0.1.5
