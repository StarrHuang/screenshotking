# ScreenshotKing

<p align="center">
  <img src="resources/branding/screenshotking-logo-v1.png" width="104" alt="ScreenshotKing crown and screenshot frame logo">
</p>

<p align="center">
  <strong>Native macOS screenshots, rich annotations, and local clipboard history.</strong><br>
  Capture quietly. Save and copy right away. Annotate when you need to.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a> · <a href="https://github.com/StarrHuang/screenshotking/releases/latest">Latest release</a> · <a href="docs/releases/0.3.0-build12.md">Build 12 notes</a>
</p>

**macOS 15+ · Apple Silicon · 2.3 MiB download**

ScreenshotKing is a native, menu bar screenshot and clipboard utility built with AppKit, SwiftUI, ScreenCaptureKit, and Vision. It has no Electron shell, account, or bundled third-party runtime. Its interface is currently primarily in Simplified Chinese.

| Need | What ScreenshotKing does | Default |
|---|---|---|
| Capture without breaking focus | Saves a capture and copies it to the clipboard | Silent save and copy |
| Add context to a screenshot | Reopen a capture for notes, steps, and visual markup | Editor opens on request |
| Reuse copied material | Search and organize local text, rich text, images, and files | Clipboard monitoring off |

> **Download:** [ScreenshotKing 0.3.0 build12 for Apple Silicon](https://github.com/StarrHuang/screenshotking/releases/download/v0.3.0-build12/ScreenshotKing-0.3.0-build12-macOS-arm64.zip) · [SHA-256 checksums](https://github.com/StarrHuang/screenshotking/releases/download/v0.3.0-build12/SHA256SUMS.txt)
>
> This is an ad hoc signed development build and is not notarized by Apple. macOS may ask you to approve permissions again after a rebuild or signature change.

## Capture, save, and keep working

By default, a finished capture is saved silently and copied to the system clipboard. ScreenshotKing does not open its editor or a save dialog automatically. Choose **Edit Recent Screenshot** from the menu bar or File menu, or open a capture from the library, when you want to annotate it. Silent saves use your configured folder, or `~/Pictures/ScreenshotKing` if none is set.

![ScreenshotKing editor with a captured image and annotation toolbar](docs/assets/editor-build12.png)

### Screenshot and recording

- Capture a region, window, or screen; repeat the last selection, set a delay, or choose a fixed ratio or pixel size.
- Capture long vertical or horizontal pages by scrolling automatically or adding sections manually. Long capture is limited to 30 frames; compatibility with dynamic pages and sticky headers still needs broader verification.
- Record the screen with optional system audio. System audio, microphone, and camera are off by default. Microphone and camera recording paths have not been live-verified for this release.

### Annotate when needed

The editor includes notes and numbered steps with explanations, shapes, arrows, freehand and highlighter tools, text, number markers, pixelation and blur, crop, stickers, magnifier, highlights, and tiled watermarks. Adjust object appearance, move or copy objects, undo and redo, and export PNG, JPEG, or HEIC.

![Native ScreenshotKing build 9 export showing notes and numbered steps with explanatory text](docs/assets/notes-and-steps.png)

*Actual app export from a synthetic note-and-step test in build9.*

<details>
<summary>Annotation renderer sample</summary>

This image is a renderer test sample, not a screenshot of the app toolbar.

![Renderer test sample showing annotation styles on a synthetic image](docs/assets/annotation-tools.png)
</details>

Editable `.skedit` source is saved when working through the editor and library. A raw capture saved in the default silent flow is not automatically an annotated project.

### Local clipboard history

Clipboard history can retain text, rich text, images, and multiple files with their item formats and order. Search, favorite, tag, categorize, copy in the original format or as plain text, and back up or restore history. Clipboard monitoring is **off by default**; active paste is optional and requires Accessibility permission.

### OCR and translation

Use Apple Vision for local text and QR/barcode recognition. Apple Translation can translate recognized text or create a translated image overlay. Offline language assets may need to be downloaded first; English-to-Simplified-Chinese translation has been verified on this machine.

## Implementation at a glance

| User outcome | Implementation | Source |
|---|---|---|
| Capture a screen region or record a clip with native macOS frameworks | AppKit capture flow and ScreenCaptureKit recording | [`Capture.swift`](Sources/Capture.swift) · [`Recorder.swift`](Sources/Recorder.swift) |
| Save editable notes and numbered steps, then reopen the project | Annotation objects are stored in `.skedit` JSON with source and working PNG images | [`ImageEditor.swift`](Sources/ImageEditor.swift) · [`AnnotationStyle.swift`](Sources/AnnotationStyle.swift) |
| Keep clipboard history locally with item types and formats | Structured pasteboard entries, search, and history management | [`Clipboard.swift`](Sources/Clipboard.swift) |
| Recognize text and codes, then translate with Apple Translation | Vision recognition and system translation integration | [`ImageIntelligence.swift`](Sources/ImageIntelligence.swift) |
| Export captures without overwriting an existing file | Image encoding and collision-safe output naming | [`Export.swift`](Sources/Export.swift) |

The release ZIP is **2.3 MiB** and the installed app is about **4.7 MiB**. These are package-size measurements, not speed benchmarks.

## Install and use

1. Download the Apple Silicon ZIP above and expand it.
2. Move `ScreenshotKing.app` to Applications and open it.
3. Allow Screen & System Audio Recording when prompted to capture. Accessibility permission is needed for automatic scrolling and active paste.
4. Capture with a shortcut, then open **Edit Recent Screenshot** when you want to annotate.

The app UI is primarily in Simplified Chinese. These menu labels are useful when navigating it:

| English | Menu label |
|---|---|
| Edit Recent Screenshot | 编辑最近截图 |
| Screenshot Library | 截图库 |
| Settings | 设置 |

Default shortcuts:

| Action | Shortcut |
|---|---|
| Region / window capture | `⌃⌥⌘1` |
| Clipboard history | `⌃⌥⌘2` |
| Repeat previous selection | `⌃⌥⌘3` |
| Long screenshot | `⌃⌥⌘4` |
| Start / stop recording | `⌃⌥⌘R` |

Shortcuts can be changed in Settings. Press Escape to cancel a capture.

## Build and run tests

Requirements: macOS 15 or later, Xcode command-line tools, and an Apple Silicon Mac.

```sh
./scripts/build.sh
open build/ScreenshotKing.app
./scripts/test.sh
```

The app is implemented in Swift using AppKit and SwiftUI. Screen capture and recording use ScreenCaptureKit; OCR and code recognition use Vision; translation uses Apple Translation. The test script covers geometry, image export and processing, document recovery, local clipboard behavior, OCR, and QR recognition. These tests use a private pasteboard; native QA helpers are a separate matter and can touch the system clipboard.

See the [capture and annotation guide (Chinese)](docs/screenshot-workflow.md) for detailed usage, and [GitHub publishing and README maintenance notes (Chinese)](docs/github-publishing.md) for the repository's publication and localization approach.

## Scope and verification

ScreenshotKing is independently implemented. It does not import another app's clipboard database or link its executable, private interfaces, or resources. It has no iCloud synchronization. This repository does not currently include a software license.

The release verifies silent save and clipboard image output, reopening a capture for editing, and selected annotation and clipboard behavior. Some areas have implementation or automated coverage without complete live verification, including microphone and camera recording, dynamic long-page layouts, and full compatibility with other screenshot tools. See the [verification record](docs/verification.md) and [feature coverage matrix](docs/parity-matrix.md) for evidence and limits.

## Feedback

Found a bug or have a feature request? [Open an issue](https://github.com/StarrHuang/screenshotking/issues) and include your macOS version, Mac model, and steps to reproduce when relevant.
