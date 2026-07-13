# FrameScript v0.4.0

FrameScript v0.4.0 makes production planning easier to navigate and ships as a downloadable macOS app:

- Configure keyboard shortcuts by recording them in Settings, safely reassign conflicts, explicitly unassign commands, and keep reserved system shortcuts protected. Menu commands and visible keycaps update immediately, while letter shortcuts follow physical key positions across keyboard layouts.
- Explore a complete, disposable five-scene product showcase in English or Russian with script, Visuals, Editing, and prepared local review content. Demo edits are discarded unless you explicitly save a project file.
- Keep Visuals and Editing relationships anchored to exact script text through ordinary edits, with clearer grouping and marker navigation. Substantial or ambiguous rewrites can still clear links that cannot be repaired safely.
- Use simpler Settings and launch behavior, with AI review and inline autocomplete enabled by default for new or reset settings and a persisted autocomplete control.
- Get more reliable inline-autocomplete wrapping, editor geometry, production markers, and anchor repair.
- Install from a universal `FrameScript.dmg` for Apple Silicon and Intel, with a ZIP fallback and published SHA-256 checksums.

FrameScript continues to write `.fscr` project format version 3, reads versions 1–3, and imports legacy `.framescript` files.

The v0.4.0 app is ad-hoc signed and is not Apple-notarized. After copying it to Applications, Control-click FrameScript, choose **Open**, and confirm **Open**. If macOS still blocks it, use **System Settings → Privacy & Security → Open Anyway**. Inline review markers are not yet shown in the editor, AI features require a configured provider and network access, and arbitrary ambiguous rewrites cannot always preserve production anchors.
