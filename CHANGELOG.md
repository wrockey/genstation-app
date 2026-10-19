# Changelog

## 2.1 — final source, never released (October 2026)

This is the last version of GenStation. It was prepared for the App Store but not submitted; the app
was withdrawn and the source published under the MIT License instead.

**Providers and models**
- Repaired image and video generation for Google Gemini, xAI Grok and AI/ML API after provider changes.
- Curated model catalog with per-model request schemas captured from the providers, replacing the
  older hand-written model registry. Unsupported or retired models are locked out instead of failing.
- Model favorites and search; GPT Image 2/2.5 edits with up to 16 reference images.
- Simpler single-provider setup with connection checks that do not generate anything.

**Library and jobs**
- Revise and Animate actions on history items prepare new image or video drafts.
- Jobs panel for in-flight work, recovery of already-generated results after a failed download or
  restart, and provider-reported costs where available.
- Mac: Copy Image, fixes to full-screen export and to stale history thumbnails.
- Mac: paint-to-edit mask inpainting for GPT Image models.

**ComfyUI**
- Durable named saved workflows, named workflow inputs, and recovery of existing outputs without
  resubmitting.

**Agents (macOS, experimental)**
- Local MCP server running inside the app's own sandbox, with signed-peer authentication.
- Image generation and editing with individual approval in the app, durable request IDs, job
  discovery and waiting, scoped access to originals, history folders and palette styles.
- AI/ML API video and saved ComfyUI workflows through MCP, each individually approved.
- Optional spending-threshold approval for AI/ML API and xAI images (off by default, not tested live).

## 2.0 — February 23, 2026

First 2.x App Store release.

## 1.0.1 — December 2025

App Store bug-fix release for iOS and macOS.

## 1.0 — December 2025

First App Store release for iOS and macOS.
