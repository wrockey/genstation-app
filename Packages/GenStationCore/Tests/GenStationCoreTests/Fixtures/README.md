# Captured AI/ML API metadata

**Captured 2026-08-11** (previously 2026-07-27) against `https://api.aimlapi.com`, using the key
stored in the app's own keychain item (`service = art.genstation.app`, `account = aimlapi_key`).
Two documentation/metadata endpoints only — **no generation request was made and no generation
credits were spent.**

| File | Source | Contents |
|---|---|---|
| `aiml-models-response.json` | `GET /models` | 902 entries, **760 unique ids** |
| `aiml-model-schemas.json` | `GET /docs-json?model=…&endpoint=…`, one call per model | 172 OpenAPI 3.0 documents, keyed by the canonical served id (167 as of 2026-07-27; five more — the intake ids for Nano Banana 2, Nano Banana 2 Lite, Seedream 5.0 Pro and FLUX.2 Max — were captured 2026-08-11) |

Both are normalised — `indent=1`, `sort_keys=True`, `data` sorted by `id` — so a **re-capture produces a
reviewable diff** rather than a reordering. Re-capture by calling the same two endpoints with your own key and normalising the output the same way.

Checked for secrets before committing: the request key does not appear in either body, and there are no
`email` / `user_id` / `account` / `organization` / `token` / `secret` keys. Neither file contains pricing.

## Why these exist

Earlier design notes stated that **there is no source
of truth in this repository for what any model's API actually accepts**, and that making the parent spec's
§ 8.3 invariant ("descriptor enums match documented capabilities") real would require a live probe harness
that "costs credits; that is a user decision".

That is now out of date in both directions. `/models` publishes per-model metadata the app was throwing
away, and every served model publishes a **complete request-body schema** — parameters, types, `enum`s of
legal values, defaults and the required set. These files are that source of truth, captured and pinned.

## What `/models` carries that the app used to discard

`AIMLModelEntry` decoded `{id, aliases}`. Every entry actually has **five** fields:

| Field | Coverage | What it gives us |
|---|---|---|
| `type` | 902/902 | The real task split. `internal/video-generations/submit` **210**, `openai/image-generations` **127**, `openai/image-editing` **5** — and **560 entries that are neither** (339 `openai/chat-completions`, 60 `openai/responses/submit`, 27 `anthropic/messages`, TTS, STT, embeddings, OCR). This replaces the 35-token string heuristic, whose video branch has no negative filter. |
| `info.name` | 902/902 | A real display name (`"Sora 2 Text to Video"`). |
| `info.developer` | 902/902 | The vendor, which seeds `family`. |
| `info.releasedAt` | 894/902 | Recency ordering. **8 entries lack it** — any sort needs a defined fallback. |
| `info.isHottest` | 57/902 | The vendor's own "recommended" set. |
| `info.description` | 770/902 | Row subtitles. |
| `info.docsUrl` / `info.docsJson` | 902/902 | `docsJson` is the per-model schema fetched into the second file. |
| `tags` | 902/902 | `playground:video` / `playground:image` — a second confirmation of `type`. |

**No pricing field exists**, which is why the catalog shows observed cost from history rather than an
estimate (spec § 4.5).

## Known gotcha when re-capturing

`docs-json` returns **403 Forbidden** to a `Python-urllib` User-Agent and 200 to `curl`. Use `curl` (or a
real client UA). The app itself is unaffected — `URLSession` sends its own bundle User-Agent. A blanket
403 across every model means the User-Agent, not the key and not a rate limit.

## What the schemas already proved

Comparing every registered model's emitted payload keys (from `GoldenPayloads`) against its published
schema: **68 of 201 checked ids emit at least one key their own schema does not document.** Most frequent:
`aspect_ratio` (25 ids), `camera_control` (18), `enhance_prompt` (14), `generate_audio` (13),
`shot_type` (12), `negative_prompt` (10).

The offenders cluster in `wan26Video`, `wan26VideoI2V`, `klingVideo` and `seedreamV4` — **exactly the four
tables Stage 2 marked `unverified: copied from the shared <X> view`.** The marker was honest.

Two caveats, both load-bearing:

- **An undocumented key is not proof of rejection.** Many APIs ignore unknown fields. The likely effect of
  e.g. `generate_audio` on a model whose schema has no audio parameter is that the feature silently never
  happens — not that the request fails.
- **This is a baseline, not a bug list to fix on sight.** Every correction moves the wire for existing
  users, so each one belongs in the drift ledger as a group-A row
  awaiting approval — never as a table edit.
