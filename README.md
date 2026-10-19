# GenStation

GenStation is a native SwiftUI app for macOS and iOS that creates and revises AI images and videos
through services you already have accounts with. It keeps the originals and their generation details
together in a local history.

- **Providers:** Google Gemini, xAI Grok, AI/ML API (a gateway to many image and video models) and your
  own ComfyUI server. You bring your own API keys; the app has no backend of its own.
- **Library:** searchable history with folders, revise/animate actions, recovery of finished jobs, and
  tar.gz export/import.
- **On-device upscaling:** 4x Real-ESRGAN via Core ML.
- **Agents (macOS only, experimental):** an optional local [Model Context Protocol](https://modelcontextprotocol.io)
  bridge lets agent tools such as Claude Code discover models, request images with your approval in the
  app, and retrieve the originals. See [tools/genstation-mcp](tools/genstation-mcp/README.md).

## Project status: archived

GenStation was published on the Apple App Store from 2025 to 2026 and has since been withdrawn. This
repository is the final source, released under the MIT License, and **is not maintained**. Issues and
pull requests are not monitored.

Model lists and request formats were last checked against the providers in September 2026.
Providers retire and rename models often, so expect some models to fail and the curated list to need
updating (see [Updating the model list](#updating-the-model-list)).

The public history starts from a single snapshot commit. Some code comments refer to internal
development stages, tasks or commit IDs from the earlier private history; they are kept for context
and do not affect the build.

## Requirements

- A Mac with **Xcode 26** (the project was last built with it; Xcode 16 or later may work).
- macOS 14 or later to run the Mac app; iOS/iPadOS 17 or later for the iPhone/iPad app.
- An API key for at least one provider, or a reachable ComfyUI server. Generation charges are billed by
  the provider, not by this app.

## Building and running

1. Clone the repository and open `GenStation.xcodeproj` in Xcode. Swift Package Manager fetches the
   dependencies automatically.
2. Select the **GenStation** target, open **Signing & Capabilities**, choose your own **Team**, and change
   the **Bundle Identifier** to one you own (for example `com.yourname.genstation`). The original
   `art.genstation.app` identifier is registered to the original developer's account and cannot be
   reused. Do the same for the **genstation-mcp** target (team only).
3. Choose a destination (My Mac, an iPhone, or a simulator) and press Run.

### Installing on your own iPhone without the App Store

- **Free Apple ID:** Xcode can install the app on your own device with a free "Personal Team". Apps
  installed this way stop launching after 7 days and must be reinstalled from Xcode, and a free account
  can have only a few such apps installed at once. The app uses only basic capabilities (network
  access and user-selected files), so it should not need a paid account, though this route has not
  been tested.
- **Paid Apple Developer Program:** installs last a year, and you can distribute to others through
  TestFlight.

On the Mac, a Debug build runs locally without any account. The MCP agent bridge in a **Release**
build only trusts a helper signed by the same team as the app, so sign with a team if you want to use
it outside Debug.

### Tests

The core logic (catalog, parameter encoding, providers, history, agent jobs) is a Swift package with a
provider-free test suite:

```bash
cd Packages/GenStationCore
swift test
```

The MCP helper has its own mock-socket tests; see [tools/genstation-mcp](tools/genstation-mcp/README.md).
Do not run `live_socket_test.py` casually: its generation cases can spend provider credit against a running app.

## Using the app

See the [user guide](docs/USER_GUIDE.md). In short: run the setup wizard, paste one provider's API key,
run its connection check, pick a model and generate.

API keys are stored in the system Keychain. Prompts and input images are sent only to the provider you
select (and, for AI/ML API, to the underlying model vendor). Optional ImgBB hosting creates public links
for input images on models that require URLs. The app itself collects no analytics.

## Known limitations

- **Model drift.** The curated model catalog and request schemas date from September 2026.
- **Agent bridge (macOS).** Basic image generation, polling and original retrieval were tested with
  real agents. Video requests through MCP, reconnecting during a running job, and some denial and
  failure paths were not tested end to end. Only local agents are supported, not cloud-hosted bots.
- **Spending-threshold approvals.** Letting agents run several AI/ML API or xAI image requests under a
  user-set budget is implemented but was never tested live. It is off by default ("ask every time").
- **ComfyUI.** Single-server use and saved workflows work. Support for several or password-protected
  servers was only partly built. Complex subgraph workflows may not import.
- **Demo mode.** The code contains a separate "demo" storage mode used for producing screen recordings.
  Its build configuration is not included and it is inactive in normal builds.

## Updating the model list

The catalog is data in `Packages/GenStationCore/Sources/GenStationCore/Catalog/`, and each model's
parameters are a table in `Packages/GenStationCore/Sources/GenStationCore/Params/Tables/`. A model is
offered only when it is admitted by `ReleaseModelPolicy`. [GenStation/CLAUDE.md](GenStation/CLAUDE.md)
explains the architecture and the steps to add or change a model; it is written for both people and AI
coding assistants.

## Repository layout

| Path | Contents |
|---|---|
| `GenStation/` | The SwiftUI app (shared macOS/iOS target) |
| `Packages/GenStationCore/` | Platform-independent core logic and its tests |
| `tools/genstation-mcp/` | MCP stdio server, launcher and test scripts (macOS) |
| `tools/stage3-catalog-gen/` | Scripts that generated the catalog rows from captured provider metadata |
| `tools/` | Other development and regression scripts |
| `docs/USER_GUIDE.md` | User guide |

## License

MIT; see [LICENSE](LICENSE). Bundled and third-party components are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). If you reference this software in published work, see
[CITATION.cff](CITATION.cff).

This project is not affiliated with Google, xAI, AI/ML API, ComfyUI or any other provider named here.
