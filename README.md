# TodoPilot

TodoPilot is a privacy-first macOS task capture app that turns text on your screen into actionable tasks while keeping screenshots and recognized text on your Mac.

The Free edition is designed to work entirely on-device. Capture a region, review the locally recognized text, confirm the task, and keep moving from your Today List.

## Highlights

- Capture any screen region with a global keyboard shortcut.
- Recognize text locally with Apple Vision OCR.
- Review and edit the title, notes, priority, and due time before saving.
- Manage active, completed, snoozed, deleted, and restored tasks locally.
- Import task candidates from Apple Calendar and Reminders.
- See upcoming work in the status island and receive flight-style reminders.
- Monitor local Codex, Claude Code, and Cursor task lifecycle events.
- Export local task data as Markdown or CSV.

## Privacy

TodoPilot Free is offline-first:

- Screenshots and OCR text remain on your Mac.
- Tasks are stored locally.
- There are no accounts, subscriptions, cloud AI requests, payment flows, or remote telemetry.
- Local diagnostics exclude task bodies, raw OCR text, screenshot paths, credentials, and user identifiers.

Screen Recording permission is required only for region capture. Calendar and Reminders access is optional and requested only when you use local calendar import.

## Requirements

- macOS 14 or later
- Xcode 26.5 or later
- XcodeGen 2.45.4 or later when regenerating the Xcode project

## Build and Test

Clone the repository and open the included Xcode project:

```bash
git clone git@github.com:blockdancez/TodoPilot.git
cd TodoPilot
open TodoPilot.xcodeproj
```

To regenerate the project and run the unit tests:

```bash
xcodegen generate
xcodebuild test \
  -scheme TodoPilot \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO
```

## How It Works

```text
Screen capture
  -> Apple Vision OCR
  -> Local task draft
  -> User review and confirmation
  -> Today List
  -> Status island and reminders
```

OCR output is always treated as a draft. A task enters the Today List only after user confirmation.

## Code Agent Integration

TodoPilot can install local lifecycle hooks for supported Codex, Claude Code, and Cursor versions. The hooks send minimal lifecycle metadata to TodoPilot through a local Unix domain socket. Prompt text, task bodies, project contents, and credentials are not forwarded.

Hook installation updates only the selected provider's local configuration. Existing configuration is validated and preserved, and TodoPilot-owned entries can be removed from Settings.

## Project Layout

```text
TodoPilot/             Main macOS application
TodoPilotAgentHook/    Local Code Agent lifecycle helper
TodoPilotTests/        Unit tests
TodoPilotUITests/      UI tests
scripts/               Local build and packaging helpers
project.yml            XcodeGen project definition
```

## Contributing

Issues and focused pull requests are welcome. Please keep the Free edition offline-first: screenshots, OCR text, task content, credentials, and personal identifiers must remain on the user's Mac.

Before submitting a change, run:

```bash
xcodebuild test -scheme TodoPilot -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

## Third-Party Marks

Codex, Claude Code, and Cursor names and icons belong to their respective owners. They are used only to identify local task sources and do not imply endorsement or partnership. See [`TodoPilot/Resources/THIRD_PARTY_BRAND_ASSETS.md`](TodoPilot/Resources/THIRD_PARTY_BRAND_ASSETS.md) for attribution details.
