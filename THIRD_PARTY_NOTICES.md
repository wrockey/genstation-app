# Third-party notices

GenStation's own source code is released under the MIT License (see `LICENSE`).
It includes or depends on the following third-party work, each under its own license.

| Component | Used for | License | Source |
|---|---|---|---|
| Real-ESRGAN (model architecture and weights) | On-device 4x image upscaling | BSD 3-Clause | https://github.com/xinntao/Real-ESRGAN |
| Real-ESRGAN Core ML conversion (`GenStation/RealESRGAN.mlpackage`) | Bundled Core ML model | MIT | https://github.com/john-rocky/CoreML-Models |
| SWCompression | History export/import (tar.gz) | MIT | https://github.com/tsolomko/SWCompression |
| BitByteData | Dependency of SWCompression | MIT | https://github.com/tsolomko/BitByteData |
| SDXL-A1111-Styles (Douleb) | Built-in prompt style presets (`GenStation/Resources/prompt_styles*.json`) | MIT | https://github.com/Douleb/SDXL-A1111-Styles |
| StableDiffusion-Style-Database (naughtynarratives) | Built-in prompt style presets | MIT (as recorded in the style file) | https://github.com/naughtynarratives/StableDiffusion-Style-Database |

The built-in style list also includes community-shared prompt styles from unrecorded sources.

Swift packages are fetched by Swift Package Manager at build time; their exact versions are pinned in
`GenStation.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`.

## Captured provider metadata

`Packages/GenStationCore/Tests/GenStationCoreTests/Fixtures/` contains model lists and request
schemas captured from the public AI/ML API documentation endpoints (2026). They are included only
as test fixtures that pin the app's request encoding. They remain the property of their publisher.

## Trademarks

Google Gemini, xAI Grok, AI/ML API, ComfyUI, ImgBB, OpenAI and the other model and provider names
in this repository are trademarks of their respective owners. They are used only to identify the
services the app connects to; this project is not affiliated with or endorsed by any of them.
