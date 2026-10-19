# genstation-mcp: local agent access (macOS)

GenStation for macOS includes an optional local [Model Context Protocol](https://modelcontextprotocol.io)
server. Compatible local agent clients (for example Claude Code or other MCP-capable command-line tools)
can discover models, validate requests, ask GenStation to generate images (and AI/ML API videos) with the
user's approval, follow the resulting jobs and retrieve the originals. The app holds the API keys; the
agent never receives them.

**Status:** experimental and unmaintained. Basic image generation, polling and original retrieval were
tested with real local agents. Video through MCP, reconnecting during a running job, some denial and
failure paths, and spending-threshold approvals were not tested end to end. Cloud-hosted bots are not
supported.

## How it works

`Contents/Helpers/genstation-mcp` in the app bundle is a symlink to a small sealed launcher script in
`Contents/Resources`. The launcher executes `Contents/MacOS/GenStation --genstation-mcp`, so the stdio
server runs as the app's own executable inside the app's own sandbox. It does not build any UI or read
the Keychain; it relays requests over a private Unix socket to the running GenStation app, which
performs validation, approval and generation.

The app authenticates each socket peer: it must be the app's exact main executable, with an
Apple-anchored signature, the app's bundle identifier and the same signing team as the running app
(Mac App Store re-signing is also accepted). Debug builds skip the signature check so local development
works unsigned. The launcher only opens its own containing app, never another installed copy. Moving
the app requires updating the client's configured path. Run `connection_status` and check
`mcp_execution`, `app_path` and `server_executable_path` to see which installation is active.

Local clients must be allowed to start this executable in its own App Sandbox. A client that forces an
inherited sandbox may prevent startup; do not add inheritance entitlements or relax the app's
protections to work around a client's policy.

## Setup

Enable Agent Access in GenStation Settings and use **Copy MCP Setup Command** to register the bundled signed helper. `connection_status` checks the socket/app, durable job storage and which provider keys are configured. It performs no provider calls and does not verify credentials. Use the app's provider connection check to verify a key.

Start with `list_models` using `{"type":"image"}`. Each image entry supplies an explicit `provider`, model ID, `parameter_schema`, input limits and unknown-price approval policy. Native Gemini and Grok are separate from AIMLAPI, even when a similar model is sold through AIMLAPI. Only curated image paths are exposed; image inputs go directly to the chosen provider as data URIs.

1. Call `validate_image_request` with the intended arguments. This decodes/validates inputs and builds the request locally; it does not upload, generate, request approval, or reserve a request ID.
2. Call `generate_image` with the same arguments plus a stable `request_id`. Keep the ID and the exact arguments for recovery. The app returns a durable `job_id` immediately. Ask every time remains the default. The user may deliberately enable scoped AIML/xAI image **spending-threshold approval** in Agent Access. Eligible jobs queue and run serially while exact recorded spending is below the chosen budget. The final request can exceed it. Missing or invalid response billing pauses automatic work; a failed request can still count as charged. No advance price maximum is required. Grants end at expiry or app quit, and durable accounting survives. Connected agents share the active grant; only the user can change it. Legacy preferences never activate a grant. Video, Gemini and workflows retain individual approval.
If you close or defer the approval review, the request stays pending while GenStation remains open. Reopen it from **Jobs → Pending Approvals → Review**, or explicitly Deny it there. Do not create a replacement request ID merely because the review window was dismissed. Pending review payloads are not restored after quitting the app; existing restart/interruption rules still apply.

3. Poll `get_job_status`. Budget image states also include `budget_queued`, `budget_exhausted`, `billing_unresolved`, `grant_revoked`, `grant_expired` and `storage_unavailable`. On a pause, retain the existing identity and tell the user; never submit replacement IDs to bypass it. Connection diagnostics and budget job status expose `spending_approval` with exact totals, scope and unresolved billing. Image states are `awaiting_approval`, `submitting`, `saving`, `done`, `denied`, `interrupted`, or `failed`. `billing_status` is `not_submitted`, `unknown`, `billing_unresolved`, or `reported`; only reported costs include `cost_usd`. Failed/interrupted requests may still have been charged. Credit errors include `error_code: insufficient_credits`.
4. On completion, pass an `asset_id` to `get_asset` for the original path and inline preview. Use `asset:<asset_id>` in a later request's `input_images` to revise that original. `list_assets` returns up to 100 recent workflow-created or explicitly shared originals. Share or revoke other originals from their library menu; agents cannot grant themselves access or submit arbitrary paths/remote URLs.

Example arguments (use a model actually returned by discovery):

```json
{
  "provider": "gemini",
  "model": "gemini-2.5-flash-image",
  "prompt": "A small ceramic lighthouse on a blue table",
  "params": {"aspect_ratio": "1:1"},
  "request_id": "lighthouse-first-2026-09-13"
}
```

AIML `openai/gpt-image-2`, `openai/gpt-image-2.5-flare` and `openai/gpt-image-2.5-sunburst` accept up to 16 optional edit references within the shared size limits. `requires_input_image: false` means references are optional, not unsupported. Supply them in top-level `input_images`, with `size`, `quality` and `background` in `params`. Validation builds the multipart `/v1/images/edits` request locally without uploading. With no references, generation still uses JSON `/v1/images/generations`. Discovery includes readable names and descriptions; Flare is positioned for speed and Sunburst for demanding quality ([OpenAI model guidance](https://developers.openai.com/api/docs/guides/image-prompting)). `price_status: unknown` describes advance pricing and is independent of edit capability.

For revision, use a **new** request ID, revised prompt, and `"input_images": ["asset:<previous-asset-id>"]`. Image provider requests run serially; eligible budget jobs can queue. Inputs total at most 20 MB and each image at most 64 megapixels; model-specific counts are in discovery. The initial contract limits requests to one output and supports a subset of image-size controls; preflight rejects options it cannot encode faithfully.

If the connection drops, repeat **the same request ID and identical arguments**. It returns the existing job and never repeats its POST. Changed arguments with an existing ID are rejected. After an interrupted submission, inspect the library and provider billing before explicitly deciding to create a new paid request. Recovery never auto-submits. Provider asset URLs are retained for download recovery; a generated original is staged locally before moving it to the configured folder.

For AIML video, discover `list_models` with `type: video`, then call `validate_video_request` locally. Submit `generate_video` with a stable `request_id`; it returns a job immediately and asks for individual approval. Repeat identical arguments and ID to retrieve that job without another POST. Video inputs are data URIs only; configured public ImgBB hosting happens only after approval and is disclosed in the dialog. No native Gemini/Grok video MCP expansion is included.

Poll `get_job_status`. Known provider IDs survive restart; `recover_video_job` resumes GET-only status/download recovery without generating again. If the submission response was lost before its provider ID was saved, `submission_unknown` accurately records the uncertainty and never resends. Pre-upgrade video jobs remain readable but cannot retroactively acquire durable request IDs. Remote MCP and arbitrary workflow execution remain excluded.

## Saved workflows with named inputs

Use `list_workflows` to discover saved IDs, `workflow_revision`, `workflow_digest` and `input_schema`. Supply only exposed input names with both revision and digest. Legacy `prompt` remains supported for workflows without an exposed prompt input. Filenames, server URLs, raw graphs and arbitrary node bindings are not accepted from clients.

In the app, save a workflow, choose **Edit Named Workflow Inputs**, select compatible literal prompt/negative/image/seed/dimension fields and save the mappings. **Run Saved Workflow…** provides the equivalent reviewed GUI path; an original's library menu can open it with that image selected. This prepares a draft and never grants agent access by itself.

`validate_workflow_request` reads live node definitions and authorized local originals without uploading. Image values are `asset:<UUID>` references to scoped PNG/JPEG originals, at most four images, 40 megapixels per source and 20 MB of prepared PNGs total. `run_saved_workflow` requires a durable `request_id` and individual app approval. Graph/server/input identity and access are rechecked after approval; unique PNG uploads never overwrite server files. Interrupted upload and uncertain generation submission are distinct states. Never automatically resend either under a new request ID.

Up to four selected output nodes return at most 12 files, 50 MB per file and 200 MB total. Each output retains its original bytes, ID, available dimensions, media type and parent/workflow/input lineage. Partial download recovery skips saved originals; it never POSTs generation. `get_asset` returns image previews when available and supported video original paths with `preview_available: false`. Video dimensions can be unavailable when the platform cannot inspect the container. Unsupported formats remain recoverable with a clear error, rather than being disguised as images.

The shared text policy checks effective positive prompt text before uploads/submission, including saved values without an override. Negative-only branches and file/model selectors are excluded. Recognized linked/custom prompt inputs are reported as inspection limitations; this does not guarantee complete graph inspection or visually moderate media.

## Agent onboarding built into MCP

The helper supplies concise `instructions` in the `initialize` response and advertises a static Markdown resource at `genstation://docs/image-workflow`. Clients discover it with `resources/list` and read it with `resources/read`. It covers every tool, provider/model discovery, limits, examples, approval, polling, durable request IDs, failure/billing uncertainty, scoped originals and durable video recovery. Essential rules also remain in tool descriptions for clients that do not surface resources.

The canonical agent-facing text is compiled from `AgentDocumentation.swift`; it does not depend on this README or repository access. Reading documentation does not launch/connect to the app or contact a provider. No resource subscriptions or change notifications are advertised; `resources/templates/list` returns an empty list. Unsupported URIs are rejected instead of interpreted as file paths.

After updating the app, reconnect or restart the MCP client so it receives fresh initialization instructions. Use the helper embedded in the same app bundle that is running; if the app moved, copy the setup command again from its Settings.

## Resume and organize

Use `list_jobs` (`filter: pending` or `attention`) or `get_job_status` with exact `request_id` and `kind` after reconnecting. Wait with `wait_for_job` and the returned `state_token`; timeouts never authorize resubmission. Run `python3 tools/genstation-mcp/follow_job.py /exact/GenStation.app/Contents/Helpers/genstation-mcp --request-id ID --kind image` to follow an existing job without generating. `continuity_test.py` exercises reconnect, approval-needed once, nonblocking waits and terminal asset consumption against a mock socket.

`get_asset` returns canonical checksum/byte-count/type/dimension metadata with explicit unknown seed/parameter fields. New cloud image originals retain provider bytes. Discover folders with `list_history_folders`; create/rename a task folder and use `move_history_assets` after completion. All folder names/IDs/nesting are visible under local Agent Access; asset contents stay individually scoped. Folder membership never grants access. See the bundled guide for exact fields and retry rules.

## Filter diagnostics

Image, video and workflow validators and submission errors preserve bounded local `filter_reasons` with `filter_source: genstation_local`. Reasons identify the policy version, rule/category and a normalized phrase or category label; no original-text offsets or surrounding prompt are disclosed. Immediate errors use `error.data`; durable job failures use top-level fields where a job exists. Provider errors do not fabricate local reasons. Validate the effective request first, review rejection reasons with the user, and never automatically evade filtering. See the bundled guide for the full contract.

## Verification

All of these run on macOS. None of them is needed to use the app.

- `python3 tools/genstation-mcp/smoke_test.py /path/to/genstation-mcp` drives a standalone helper against a
  fake app socket, with app auto-launch disabled.
- `python3 tools/genstation-mcp/documentation_test.py /path/to/genstation-mcp` checks the bundled agent
  documentation offline across supported protocol versions.
- `continuity_test.py` exercises reconnects, approvals, non-blocking waits and asset retrieval against a
  mock socket.
- `python3 tools/genstation-mcp/live_readonly_test.py /path/to/GenStation.app/Contents/Helpers/genstation-mcp`
  drives the embedded signed helper against an already running Release app. It sends only invalid
  generation requests, which fail before approval, and checks that unsigned clients are rejected.
  `video_readonly_test.py` does the same for video.
- `python3 tools/genstation-mcp/verify_bundle.py /path/to/GenStation.app [--team TEAMID] [--bundle-id ID]`
  checks a built app's launcher, signature, sandbox and that no development files were packaged. Add
  `--distribution` for an App Store export.
- **Do not** run `live_socket_test.py` as an ordinary test: its generation cases can spend provider
  credit against a running app.

Build the standalone mock-test helper (the `genstation-mcp` Xcode target) from `main.swift`,
`MCPStdioServer.swift`, `SocketClient.swift` and `AgentDocumentation.swift`. A sandboxed app cannot reach
arbitrary temporary mock sockets, so use the standalone helper for mock tests and the app-embedded helper
for live tests. The core package's `AgentImageTests` and related tests cover request bytes, validation,
replay and conflict handling, storage failures and the approval, persistence and single-submission
ordering.

These tests do not establish live model availability, prices, provider reliability or the usability of
the approval dialogs.
