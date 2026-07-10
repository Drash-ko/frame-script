# FrameScript

![FrameScript demo banner](docs/banner.svg)

FrameScript is a native macOS SwiftUI app for writing YouTube scripts as structured production scenes. A scene keeps the voiceover script, B-roll plan, editing notes, AI review comments, and estimated duration together so writing and production planning stay in one focused workspace.

This repository is prepared as the first public demo snapshot of the project.

## Status

FrameScript is an early demo. The core app shell, local project format, templates, script/B-roll/editing workflows, export renderer, and Keychain-backed AI configuration are implemented.

## Requirements

- macOS 14.0 or later
- Xcode with the macOS SDK

## Run

```sh
open FrameScript.xcodeproj
```

Then select the `FrameScript` scheme, choose `My Mac`, and press `Cmd+R`.

## Features

- Scene-based script editor with English and Russian UI strings.
- Script, B-roll, and editing modes over the same scene structure.
- Built-in templates for blank, standard YouTube, educational, storytelling, product review, commentary/essay, and tutorial projects.
- Project save/open using `.framescript` files.
- Export as plain text, Markdown, CSV, or production outline.
- AI review and production suggestions for OpenAI-compatible providers, OpenRouter, and Groq when configured with API keys.
- API keys are stored in the macOS Keychain, not in project files.

## Project Structure

```text
FrameScript.xcodeproj
FrameScript/
  App/                 App entry, shell, state, dependencies
  Components/          Shared toolbar, sidebar, form, editor UI
  Core/                Theme, localization, duration utilities
  Features/            Script, B-roll, Editing, AI, Settings, commands
  Models/              SwiftData models, settings, built-in templates, demo data
  Services/            AI, export, file storage, Keychain
  Assets.xcassets      App icon and assets
docs/
  banner.svg           README banner
```

Built-in templates are defined in `FrameScript/Models/SampleData.swift`.

## Privacy And Security

FrameScript project files contain project content only. AI provider keys entered in Settings are stored through the macOS Keychain under the `FrameScript` service name.

Before publishing builds or branches, keep generated files out of Git:

- `DerivedData/`
- `.build/`
- `.swiftpm/`
- `.env*`
- provisioning profiles, certificates, and private keys
- generated repository dumps such as `repomix-output.md`

See `SECURITY.md` for reporting guidance.

## Known Limitations

- Inline AI completion and inline review markers are not exposed until the editor has real inline behavior.
<<<<<<< HEAD
- Anthropic-compatible and Gemini provider adapters are listed as future provider types but are not implemented.
- Manual UI verification is still needed for exact cursor/caret alignment across macOS text rendering configurations.
=======
- Production markers use AppKit text-range geometry and should be verified when changing typography or editor layout.

## License

No open-source license has been selected yet. Until a license is added, all rights are reserved by the repository owner.
>>>>>>> c819716 (Clean up production notes, AI providers, and exports)
