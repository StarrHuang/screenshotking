# Bounded runtime review

Review date: 2026-10-23. Requested reviewer configuration: `gpt-6.1-sol`, `medium`; actual runtime model/effort metadata is unavailable, so **unverified**.

Scope: App, Capture, CaptureGeometry, Recorder, ScrollingCapture, Pin, Settings, Library, ImageIntelligence, Clipboard, ClipboardWindow. ImageEditor and ImageProcessing internals were excluded. Review is static: no GUI operation, system clipboard inspection, or screen capture was performed. Reproduction steps below are acceptance cases for the main agent, not claims of executed UI tests. Files are being edited concurrently; line references describe the reviewed snapshot and should be resolved by symbol if shifted.

## Findings

### 1. P1 — Camera survives an early recording-start failure

- Evidence: `Sources/Recorder.swift:21-22`, `42-50`. `showCamera` starts and stores an AVCaptureSession before the throwing `SCShareableContent` query. The cleanup catch begins only at line 42, so a query error propagates to App's alert without stopping the camera or closing its panel.
- Trigger: enable camera, begin recording, let camera permission succeed, then cause the shareable-content query to fail (for example, screen capture permission revocation). Recording fails while the camera session remains active.
- Impact: continued camera use after a failed recording attempt; resource/privacy boundary violation.
- Minimum repair: make the entire start sequence, including camera setup and content lookup, share one failure cleanup path. Clear all owned resources on every thrown start error.
- Verify: inject a content-query failure after camera setup; assert session is stopped, panel closed, recorder idle. Confirm the real camera indicator turns off.

### 2. P1 — Starting is treated as idle, allowing duplicate recorders and termination

- Evidence: `Sources/App.swift:69-72`, `224-234`; `Sources/Recorder.swift:19-47`, `61-62`. The app checks only `isRecording`, which is set in an asynchronously delivered output-start callback. It replaces `recorderStorage` before awaiting start and has no starting state or guard.
- Trigger: start a recording, then invoke the recording command again during a permission prompt, content query, or stream startup. Alternatively quit in that interval.
- Impact: a second recorder can replace the first recorder's sole app stop handle; the first stream/camera may remain active without a reachable stop action. Quit can terminate an in-progress start and unfinished output.
- Minimum repair: expose an active state covering starting/recording/stopping; set starting synchronously before any await, reject another start while active, and use active for termination protection. Reset only after complete cleanup/finalization.
- Verify: introduce a deterministic startup suspension; repeat start and request quit. There must be exactly one recorder and termination must wait/cancel until inactive.

### 3. P2 — Recording controls are created after the window-exclusion snapshot

- Evidence: `Sources/Recorder.swift:22-26`, `46-47`, `86-90`. The exclusion list contains only existing app windows; `showControls()` creates a new window after capture starts.
- Trigger: select a screen region that covers the control panel's `(30, 40)` location on the primary display, or move the panel into the recording region.
- Impact: the stop/status panel appears in the saved screen video, obscuring selected content. Other app windows newly opened during recording have the same exclusion limitation.
- Minimum repair: create and order the control panel before enumerating excluded windows, then exclude its window ID. If all future app UI must stay excluded while preserving the optional camera bubble, use an application-exclusion filter with an explicit camera-window exception rather than a one-time list of all current windows.
- Verify: record the control panel's screen location, move it across the selected region, open another app window, and inspect actual output frames. The optional camera bubble must still appear when enabled.

### 4. P1 — Closing the long-capture window does not stop automatic input/capture

- Evidence: `Sources/ScrollingCapture.swift:20-25`, `58-69`, `79`. The panel has a close button but no delegate or close notification handler. Only the separate Cancel button sets `automatic = false` and `cancelled = true`.
- Trigger: start automatic scrolling, then close the window with its title-bar close button.
- Impact: the hidden task continues posting scroll-wheel input and capturing frames until duplicate detection or the frame limit stops it. It can scroll a different underlying application after the user changes focus. In-flight `addFrame()` also appends after explicit cancellation because it has no cancellation/session check after awaits (`31-46`).
- Minimum repair: route every window close through cancellation; retain and cancel the automatic task; prevent post-await capture results from committing to a cancelled or replaced session using a session identifier or cancellation check. Ensure a replacement session cannot accept an old capture's result.
- Verify: close while automatically scrolling and while a capture is suspended. No additional scroll event or frame commit may occur after cancellation; a newly started session must contain only its own frames.

### 5. P2 — Closed image windows retain their full image buffers

- Evidence: `Sources/App.swift:35-36`, `174`, `179`, `183`: editor controllers are appended indefinitely, with no close removal; individually closed pins also stay in the pins array. `Sources/Pin.swift:15`, `23` additionally makes the window own a hosting view whose root view strongly owns the same window. `Sources/ImageIntelligence.swift:50`, `63` similarly retains every translation controller forever.
- Trigger: repeatedly capture/edit and close images, repeatedly open/close translation windows, or create and close many pins. Even Close All Pins cannot break PinView's window/content-view cycle by removing controllers alone.
- Impact: large captured image buffers and windows remain allocated for the lifetime of the app; repeated high-resolution use causes unbounded memory growth.
- Minimum repair: remove closed controllers from owning collections on close; avoid PinView strongly retaining its host window (a weak reference holder or weakly captured actions suffices). Close should release the image unless the user explicitly hid a reusable pin.
- Verify: repeat opening and closing large synthetic images; use weak controller/window references to prove deallocation and confirm memory stabilizes. Distinguish Hide Pins from Close Pins in the test.

## Explicit platform gap

`Sources/App.swift:223` rejects recording on macOS 14, and `Sources/Recorder.swift:6` uses the macOS 15 recording-output API. Thus the app's screenshot/clipboard baseline is macOS 14, but recording is currently macOS 15+. If the agreed macOS 14+ requirement includes recording, this remains an acceptance blocker; supporting it requires the ScreenCaptureKit stream-output/AVAssetWriter path on macOS 14 or an explicitly revised platform boundary.

## Checked without an additional confirmed finding

- CaptureSelection's crop and stream source rectangle consistently use display-local points with a vertical flip; secondary-display global offset is kept in `globalFrame`. No concrete coordinate defect was established in the inspected conversion code.
- Original clipboard restore reconstructs each saved pasteboard item and each saved payload type rather than flattening multiple items (`Clipboard.swift:283-302`). No confirmed grouped-item reconstruction defect was established.
- Clipboard monitoring defaults off and excludes concealed/transient/sensitive marker types. This review did not execute or inspect the user's clipboard.
- Audio and camera toggles default off. Hotkey registration reports Carbon conflicts explicitly. UI/real-frontmost-application paste acceptance still requires the main agent's live verification; `paste()` appropriately reports only that a paste request was sent.

## Bounded follow-up review — long-capture targeting and cancellation

Scope limited to latest App longCapture/choose/fullCapture/recordScreen guards, ScrollingCapture targeting/loop/close behavior, and Capture window ordering. Static review only; no clipboard, screenshots, or GUI were inspected. Reviewer runtime metadata remains unverified. The CGWindowList front-to-back mapping does not introduce an established ordering defect in this snapshot. Keeping existing app windows hidden until long-capture close fixes the earlier app-window restoration interference. Remaining concrete issues:

1. **P1 — A closed session's pending frame can enter its replacement.** `ScrollingCapture.swift:22`, `34-47`, `93-95`: close sets `cancelled = true`, but a new start sets it back to false. An old `captureImage` completion then passes the cancellation guard and appends its old image to the new frame array; its defer also resets the new session's busy flag. Trigger: close during a pending frame, immediately start another long capture, then let the old capture resolve. Minimum repair: use a session generation checked after every await and before any state mutation (including defer), or keep new sessions blocked until the cancelled task has completed. Verify with a suspended capture completion and two different synthetic session images.

2. **P2 — Rapid pause/resume duplicates the automatic loop.** `ScrollingCapture.swift:67-81`: pause only flips a shared Boolean. Resume creates a second Task; if it happens before the old 750ms sleep ends, the old Task sees `automatic = true` and continues too. This doubles scrolling and interleaves frame capture. Minimum repair: retain/cancel the loop task or use an independent loop generation that invalidates the old task even after resume. Verify pause/resume within one sleep interval produces exactly one scroll per interval.

3. **P2 — The floating control panel can intercept the synthesized scroll.** `ScrollingCapture.swift:25-26`, `72-79`: the panel remains floating and visible when the target activates, while the scroll is globally posted at the selected region's center. A selection centered beneath the top-center panel sends the scroll to the control panel rather than the target content; duplicate detection then stops capture. Minimum repair: place the control panel outside the selected region, or temporarily order it out while sending scroll input (then restore without focus changes). Verify a selected region whose center overlaps the panel actually scrolls the intended document.

4. **P2 — Manual next-frame capture silently falls through after target exit.** `ScrollingCapture.swift:37-46`: a terminated target merely skips activation; it does not abort capture. After the selected app exits, Add Current Frame captures the newly exposed application at that same screen rectangle. Automatic scroll already rejects a terminated target at line 71. Minimum repair: when a previously resolved target exits, stop with an explicit status instead of capturing its replacement; reserve generic region capture for a selection that never resolved to an app. Verify close target then Add Frame leaves the existing frames unchanged and reports target exit.


## 本轮修复后的状态

build6已补会话UUID、循环UUID、Task取消、每次await后检查和当前会话defer隔离；关闭任务清理回调与图像；目标退出显示错误，按原目标窗口过滤截图，选择时按CGWindowList前后顺序排序。审阅者对这四处补丁的静态复查未发现遗留的同类具体问题。真实自动滚动仍需现场证明，静态通过不等于运行通过。

build7改用WindowServer全局事件注释路径，投递前检查选区中心最前窗口，控制面板避免覆盖中心。原PID路径的本地构造证据：滚动delta有效，但新造事件NSEvent.windowNumber为0；公开window-under-pointer字段不能补出该值。此为原因推断，接收端QAHost事件日志用于验证。

最终build9原生验证：QAHost收到全局路由后的窗口滚动事件，自动到达底部并停止，输出550×2592且OCR确认01至26行各一次。第二任务暂停/恢复/取消后事件计数及滚动条保持不变。程序坞透明高层窗口误判已通过正常/浮动应用窗口层过滤修复。该结果只证明所测普通AppKit滚动页，不扩展为全部浏览器和固定头部页面兼容。
