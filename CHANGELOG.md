# Changelog

## [Unreleased]

### Added

- Added Google AI Studio as a configurable AI provider.
- Added centralized, localized application error presentation and recovery actions.
- Added manual removal and clearing controls for Recent Projects.
- Added debounced inline AI completion with ghost text, Tab acceptance, Escape dismissal, IME awareness, and cancellation on context changes.

### Changed

- Renamed the user-facing B-roll workspace to Visuals (Видеоряд in Russian), aligned all workspace layouts, and consolidated their content inset metric.
- Integrated the Keychain explanation into the AI Settings form and widened localized workspace controls.
- Routed project, settings, export, Keychain, Recent Project, and current AI failures through one error center.
- Coalesced saved-project autosaves into a cancellable 60 ms write window.

### Fixed

- Prevented script text loss when switching modes, scenes, windows, or macOS desktops.
- Aligned the script caret, placeholder, and text with the editor column.
- Made text edits commit immediately and flush before context changes.
- Corrected Google AI Studio key storage, connection validation, and response decoding.
- Accepted the documented Google OpenAI-compatible model object, eliminated duplicate provider Keychain reads, and kept connection failures distinct.
- Preserved each scene's caret, selection, and scroll position independently per editor window.
- Prevented stale SwiftUI revisions from replacing newer editor text while still applying external rewrites.
- Restored the compact Script, B-roll, and Editing mode controls.
- Improved autosave, structured AI response, Recent Project, Keychain, and file-operation error handling.
- Updated editor metrics immediately after committed text edits, including untitled projects.
- Localized ModeSwitcher accessibility state.
- Avoided rewriting unchanged Recent Project storage during validation.
- Removed silent failure handling from critical persistence and provider operations.
- Made the complete existing surface of the Script, B-roll, and Editing controls clickable while preserving their previous visual layout.
- Removed missing Recent Projects when the application becomes active.
- Improved Recent Project bookmark validation and manual removal.
- Preserved legacy Recent data when migration persistence fails.
- Improved sandbox bookmark handling for export folders.
- Made AI analysis, rewrites, autocomplete, and production generation follow the script language with an interface-language fallback.
- Validated structured AI analysis before display, localized the AI review and Keychain information UI, and preserved earlier results during failed analysis retries.
- Replaced Keychain delete-and-add replacement with update-first storage and avoided Settings Keychain reads.

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
