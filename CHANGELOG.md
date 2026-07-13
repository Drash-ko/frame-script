# Changelog

## [Unreleased]

### Changed

- Made persisted Visuals and Editing relationships authoritative through exact text anchors; legacy segment-only links now migrate to anchors during loading and synchronization.
- Made Visuals and Editing sections, labels, selection, and marker navigation anchor-first: identical anchored ranges group together in stable script order, while invalid or missing anchors appear under Unlinked.
- Changed Script production markers to group only overlapping or touching current UTF-16 anchor ranges per Visuals or Editing lane; marker clicks now select the complete anchored group.

### Fixed

- Fixed linked production selections shifting, expanding, and shrinking through ordinary script edits, while ambiguous or unsafe repairs now clear stale relationship metadata.
- Fixed stale anchors, whitespace-separated ranges, and cross-workspace marker interaction so they no longer produce misleading geometry or selection.

## [0.3.0] - 2026-07-13

### Added

- Added inline AI autocomplete at the logical end of a script, with debounced one-sentence ghost text, Tab acceptance, Escape dismissal, IME awareness, stale-request cancellation, provider cooldowns, and localized availability details.
- Added Google AI Studio as a configurable AI provider for connection tests, AI review, rewrites, autocomplete, and production suggestions.
- Added controls to remove individual Recent Projects or clear the list without deleting project files.

### Changed

- Renamed user-facing production-footage terminology to Visuals (Видеоряд in Russian) across workspaces, AI output, exports, demo content, and current documentation while preserving compatible project-file keys.
- Changed saved-project autosave to coalesce rapid edits while editor text and live metrics commit immediately.
- Unified localized error and recovery presentation for project, settings, export, Keychain, Recent Project, and AI operations.
- Changed AI review to request and validate structured responses, preserve earlier results on failed retries, and follow the script language with the macOS language as fallback.
- Changed provider credential access so Settings uses saved-key metadata and a selected provider key is read from Keychain only for a connection test or AI request, then cached in memory until replaced or deleted.

### Fixed

- Fixed script text loss and stale-text replacement during mode, scene, window, desktop, and app-activity transitions; caret, selection, and scroll restoration are now kept per scene and editor window and clamped after shorter external updates.
- Fixed script caret, placeholder, and editor-column alignment, including insertion geometry in empty paragraphs.
- Fixed Script production-marker grouping and TextKit geometry so separate Visuals and Editing ranges retain their right-side lanes and individual hit targets.
- Fixed live word counts and scene, sidebar, and project duration estimates so they update on every committed edit, including untitled projects before save.
- Fixed the existing Script, Visuals, and Editing mode controls so their full visible surfaces are clickable and accessibility state is localized.
- Fixed Recent Project migration, bookmark validation, missing-file cleanup, unchanged-storage rewrites, and failure handling without discarding preserved legacy data.
- Fixed Keychain replacement and deletion error handling, including explicit replacement of legacy restricted entries.
- Fixed existing-provider AI review compatibility for token-truncated or harmlessly wrapped structured responses, including Groq JSON variants, while keeping parser diagnostics out of user-facing errors.
- Fixed autosave, sandbox export-folder bookmarks, settings persistence, and other critical file-operation failures that were previously silent or insufficiently recoverable.

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
