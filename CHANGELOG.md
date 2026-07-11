# Changelog

## [Unreleased]

### Added

- Added manual removal and clearing controls for Recent Projects.

### Fixed

- Made the complete existing surface of the Script, B-roll, and Editing controls clickable while preserving their previous visual layout.
- Removed missing Recent Projects when the application becomes active.
- Improved Recent Project bookmark validation and manual removal.
- Preserved legacy Recent data when migration persistence fails.
- Improved sandbox bookmark handling for export folders.

## [0.2.0] - 2026-07-10

### Added

- Added segment-linked production planning across script, B-roll, and editing modes.
- Added `.fscr` project save/open support while keeping legacy `.framescript` files readable.
- Added Groq to the configurable AI provider options.
- Added the MIT License.

### Changed

- Reworked project state management around observable document models.
- Refined project creation, template customization, settings navigation, and production-note editing.
- Updated the app icon assets and current-demo documentation.

### Fixed

- Fixed project save/open behavior and Keychain service naming for saved AI provider credentials.

### Removed

- Removed voice-preview claims from the current release documentation; this entry does not claim removal of voice-related implementation.

## [0.1.0] - 2026-07-07

### Added

- Prepared the first public demo snapshot of the macOS SwiftUI app.
- Added scene-based script writing with B-roll, editing notes, duration estimates, AI review plumbing, voice preview, and export flows.
- Documented setup, project structure, current limitations, and security expectations.

### Changed

- None.

### Fixed

- None.

### Removed

- None.
