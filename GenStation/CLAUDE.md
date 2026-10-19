# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project status

This is the final, archived source of GenStation 2.1 (unreleased successor to the App Store 2.0
build). It is no longer maintained. See the repository `README.md` for build setup, signing and known
limitations.

## Working guidelines

- Read the relevant source definitions before editing; search the repository for unfamiliar types
  rather than inventing cross-file interfaces.
- Preserve user data: history, original media and Keychain-stored API keys.
- Keep `ReleaseModelPolicy`, strict parameter validation, protected inputs, durable request IDs,
  signed-helper authentication and explicit user authorization of every paid generation. Agent
  spending-threshold approval is opt-in, serial, and pauses on unresolved billing.
- Verify claimed behavior with appropriate checks; a green build alone does not prove UI or provider
  behavior. Live provider tests can incur charges.

## Build Commands

This is a SwiftUI Xcode project. Build and run from the terminal:

```bash
# Build debug
xcodebuild -scheme GenStation -configuration Debug -destination 'platform=macOS'

# Build release
xcodebuild -scheme GenStation -configuration Release -destination 'platform=macOS'

# Open in Xcode
open GenStation.xcodeproj
```

The project uses Swift Package Manager for dependencies:
- **SWCompression** (4.8.6) - Used for tar.gz history export/import
- **BitByteData** (2.0.4) - Dependency of SWCompression

## Architecture Overview

GenStation is a cross-platform SwiftUI app (macOS/iOS) for AI image/video generation using multiple backends.

### Core State Management

The app uses a centralized `AppState` class in `App/GenStationApp.swift` that composes several `ObservableObject` substate classes:

- **`AppState`** - Root state, holds all substates and shared prompt
- **`SettingsState`** - API keys, model selection, image submission preferences
- **`UIState`** - Input image slots, output thumbnails, paths
- **`HistoryState`** - Generation history with folder support, undo/redo
- **`GenerationState`** - ComfyUI workflow parsing, node selection

### Generation Modes

The app supports four generation backends (provider identity and task selection are separate: `Provider` / `CreateTask`):

1. **Gemini** - Google's image generation models (gemini-3-pro-image-preview, etc.)
2. **Grok** - xAI's image generation/editing and native queued video
3. **AI/ML API** - Multi-provider API gateway with a curated release allowlist
4. **ComfyUI** - Local ComfyUI server with workflow JSON/PNG support

### Key File Responsibilities

| File | Purpose |
|------|---------|
| `App/GenStationApp.swift` | App state composition; domain models live in GenStationCore |
| `Shell/ContentView.swift` | Main UI layout, modal management, power panel handling |
| `Shell/ContentView+Generation.swift` | API calls, image generation logic for all backends |
| `Create/ConfigurationSection.swift` | Settings UI, API key management, model fetching |
| `Create/ModelBrowserView.swift` | The model browse surface — family sections, badges, filtering |
| `Library/HistoryView.swift` | Generation history browser with folders, search, multi-select |
| `Shell/ContentView+Batch.swift` | Batch processing logic |
| `Shared/TextEditorView.swift` | Built-in text editor for batch files (both platforms) |
| `Shared/PlatformAbstractions.swift` | Cross-platform (macOS/iOS) type aliases and utilities |
| `Settings/KeychainHelper.swift` | Secure API key storage |

### Model System (the catalog)

**There is no model registry in this target any more.** `Catalog/ModelRegistry.swift` — a dictionary of `(String) -> EnhancedModel` builders populated by `reg([ids]) { … }` — was deleted in Stage 3, along with `AIMLModel`, `EnhancedModel`, `ModelBuilder` and `enhancedModelFor(id:)`.

The catalog is data in the package:
`Packages/GenStationCore/Sources/GenStationCore/Catalog/`.

- **`CatalogModel`** — one row per model. Identity (`id`, always the lowercased canonical key, plus
  its `aliases` and its `provider`), presentation (`displayName`, `family`, `lifecycle`,
  `typicalWallClock`, `isRegistered`) and the fourteen capability fields `AIMLModel` used to carry,
  semantics unchanged.
- **`Catalog`** — a namespace enum, never instantiated. `Catalog.model(for:)` resolves aliases and
  returns an **honest `nil`** for an unknown id; `Catalog.synthesized(for:)` is the best-effort path
  for an unregistered API id and is never called implicitly — a caller opts in by name;
  `Catalog.resolve(_:)` is the two composed, for call sites that genuinely accept either.
  `Catalog.all` is the canonical rows sorted by id, and `Catalog.selectable(task:)` is what a picker
  reads: it filters `.dead` and groups by `family`.
- **`Lifecycle`** — `.current` / `.superseded` / `.dead`. Catalog lookup preserves old rows for history display. Starting a new paid request is separately gated by `ReleaseModelPolicy`, including history retries.

To add an AIMLAPI model: add its catalog row and descriptors, verify its current request schema, then explicitly admit the supported operation in `ReleaseModelPolicy`. The picker and MCP discovery filter through that policy. Capability flags and wire parameters remain separate.

The persisted `showAllAIMLModels` setting remains for decoding compatibility, but no longer expands the picker. The September 2026 repair deliberately locks out unsupported models instead of offering an experimental catch-all.

### Model Parameters (descriptor tables)

A model's parameters used to be written down three times — a hand-written SwiftUI view in
`Params View/`, a `JSONBuilder`, and a `ParameterParser` — with nothing making the three agree.
All three are gone. **A model's parameters are now one table of `ParamDescriptor` rows**, and the
control, the request body and the history re-run parse are all derived from it.

To add or change a model's parameters:

1. Write (or edit) the `[ParamDescriptor]` table in
   `Packages/GenStationCore/Sources/GenStationCore/Params/Tables/`, one file per provider
   (`VideoKling.swift`, `ImageBlackForestLabs.swift`, …). Each row names its `wireKey` (the request
   body key), its `field` (the `ModelParameters` property it stores into — **never derive one from the
   other**, they genuinely disagree for several models), its `label`/`help`, its `control`, and when it
   is visible and when it is emitted.
2. Register the table against the model ids in `Params/ParamCatalog.swift`.

Everything else follows with no further edits:

| Consumer | What it does with the table |
|----------|-----------------------------|
| `Create/ParamDescriptorView.swift` | Renders the controls. One generic view; there are no per-model views. |
| `Params/ParamEncoder.swift` | Builds the request body. |
| `Params/ParamDecoder.swift` | Parses a payload back into `ModelParameters` for history re-run. |

Notes for editing a table:

- **`Control.info(text:)` is how a model gets an explanatory panel** — the "Notes", "Input Image
  Required", "requires a video URL" blocks. Use `ParamDescriptor.info(label:text:visibleWhen:)`; it
  has no wire key, so it cannot affect a payload.
- **`help` renders as a hover tooltip on macOS and as a caption under the control on iOS.** Both come
  from the one string; don't add a separate `.info` row to say the same thing.
- **Visibility and emission are one decision.** `ParamDescriptor.isVisible(params:context:)` is called
  by the renderer *and* the encoder, so a hidden control cannot ship on the wire. The converse does not
  hold — a visible row may still be withheld by `omitWhenEmpty` or `emitWhen`.
- `GoldenPayloadTests` pins every table's output against golden fixtures across all registered ids,
  and `ParamTableConsistencyTests` checks the display half (labels, option lists, slider defaults).
  Run `cd Packages/GenStationCore && swift test` after any table edit — a red golden test means you
  changed the wire.

### History System

History uses `HistoryEntry` enum (`.item` or `.folder`). Stored as JSON at:
the app sandbox’s Application Support location (`history_v2.json`). Confirm the live container path; an older unsandboxed file may still exist.

Key constraints:
- History lookup/update must traverse folder entries; do not assume every item is at the root
- **Drag-and-drop** - iOS only, for reordering items (not for moving into folders)
- **Multi-selection** - Uses `editMode` on iOS, `isEditing` on macOS
- Moving items into folders is done via context menus/actions, not drag-drop

### Platform Abstractions

`Shared/PlatformAbstractions.swift` provides:
- `PlatformImage` typealias (NSImage/UIImage)
- `PlatformPasteboard` for clipboard operations
- Image manipulation extensions (downscaling, PNG/JPEG conversion)

### Image Submission Methods

For models requiring input images (`ImageSubmissionMethod` enum):
- **ImgBB** - Upload to ImgBB, use public URL
- **Base64** - Inline base64-encoded payload
- **Binary** - Direct binary upload

## Code Patterns

- Extensions split by feature: `Shell/ContentView+Generation.swift`, `Shell/ContentView+FileHandling.swift`, etc.
- Modal presentation via `PresentedModal` enum on `AppState.presentedModal`
- ComfyUI workflows can load from JSON files or PNG metadata
- History operations support `UndoManager` for undo/redo
