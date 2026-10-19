# Using GenStation

GenStation brings image creation, revisions, video generation and a library of originals into one native workspace. It runs on macOS 14 or later and iOS 17 or later. Local agent access is available on macOS.

## Start with one provider

Use the setup wizard to connect a Google Gemini, xAI Grok or AI/ML API account. Enter that provider's API key and run its connection check. The check authenticates without generating an image. A successful check does not guarantee that every model is available or that the account has generation credit.

In Grok mode, choose the model in the main generation panel and open Grok Settings for image aspect ratio/resolution or video duration, aspect ratio, resolution and audio. The settings pane follows the selected image/video task.

Choose an available model, enter a prompt and generate. You do not need to configure every provider, ImgBB or a custom output folder before beginning. GenStation has a default app output folder; select another folder in settings if desired. If access to a previously chosen folder is lost, select it again.

Provider accounts and generation charges are separate from GenStation. Internet access is required for cloud providers. ComfyUI uses an existing reachable server; GenStation does not install its models or custom nodes.

## Create, revise and keep originals

Choose an image model appropriate for text generation or input-image editing. Available controls and input counts depend on that model. Start with a simple prompt, inspect the result, then use the history item's Revise action to prepare another editable draft. Review the prompt, provider/model and inputs before submitting.

History and the library retain results and generation details. Search, organize with folders and use selection actions to manage multiple items. Open or share the original when you need its full saved quality; a thumbnail or agent preview is a reduced display image. On Mac, Save in the full-screen viewer exports the original through a file dialog, including when you use the default app folder. **Copy Image** in the history context menu or full-screen image context menu copies the image itself to the clipboard, not its path or thumbnail. It is also available in the viewer’s Media actions menu.

Existing inputs are protected when slots are full: remove an input before adding another.

## Video and recovery

Use a supported video model, or the history item's Animate action to prepare an image-based video draft. Input/frame support varies by model. Review the submission summary before generating. The Jobs panel tracks queued/in-progress work.

If generation succeeds but downloading or saving fails, use the available recovery action to recover the existing result. Regeneration starts another provider request and can incur another charge. Stopping local work does not guarantee the provider stopped, cancelled billing or issued a refund. A missing reported price means the cost is unknown.

## Existing ComfyUI workflows

Connect to your existing ComfyUI server and import a supported JSON workflow or workflow embedded in PNG metadata. The server must have the required models and nodes. Complex subgraph and new-modality workflows are not promised by this release. On Mac, the MCP helper can discover and run workflows you have saved in GenStation, after validation and individual approval. Other workflow inputs remain as saved; agents cannot supply arbitrary graphs, paths or uploads. This path was tested live with one saved workflow; broader workflow coverage was not.

## Local agents on Mac

Enable Agent Access in settings and use **Copy MCP Setup Command** for the installed app. Register the helper with a compatible local MCP client. The helper supplies instructions automatically and exposes `genstation://docs/image-workflow` for a complete guide.

An agent can discover supported models, validate locally, request one image, poll its job and retrieve the original. It can also search built-in/custom styles and compose a styled prompt without changing your selected styles. Negative prompts are returned separately and apply only when explicitly supported. Saved ComfyUI workflows have their own discovery, server validation and approval flow; their nodes may contact services or incur charges. Approve or deny requests in GenStation. A revision is another separately approved generation. Share an existing library original with agents from its menu; revoke access there when finished. Agents do not receive blanket library access. An agent that has already received a file may retain its own copy.

See [MCP setup and troubleshooting](../tools/genstation-mcp/README.md). After updating the app, reconnect the client; if the app's path changed, copy its setup command again. Use the helper embedded in the same app that is running.

Agent video requests also have durable request IDs and local preflight. Known provider jobs can resume status checks or downloads after restart without another generation. If a submission loses its response before a provider ID is saved, its status remains uncertain; inspect the provider before deciding to create a new paid request.

## Data and privacy

API keys are stored locally in the system Keychain and supplied to the selected service to authenticate requests. Prompts and required input media are sent to that service; AI/ML API may route them to underlying providers. Their processing and retention follow their own policies. Your configured ComfyUI server also receives its workflow and required inputs.

GenStation stores local history, generation metadata and output files. Some recovery records retain provider output URLs. Deleting a local item does not request deletion from a provider. Optional ImgBB uploads produce URLs readable by anyone who has the link; an expiry request is not a guarantee about all retained copies. The bounded MCP image path sends image inputs directly to its chosen provider; AIML video can use the configured hosting route after individual approval.

GenStation itself has no server and collects no analytics. This guide describes app behavior as of the final 2.1 source.

## Troubleshooting

- Rejected key or insufficient credit: check the selected provider account; keys for different services are not interchangeable.
- Unsupported model/parameter: choose a model and values currently offered by the app. Old history may reference retired models.
- Output folder unavailable: reconnect the drive or reselect the folder, then try recovering the existing output.
- Interrupted agent job: inspect its status and provider billing before deciding to start a new request. Reuse an existing request ID only with exactly the same arguments.
- The project is archived and no support is offered. When sharing logs or errors with anyone, redact API keys and private input media first.
