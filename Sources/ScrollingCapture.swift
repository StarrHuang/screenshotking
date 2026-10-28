import AppKit
import ScreenCaptureKit
import SwiftUI
import CryptoKit

@MainActor final class ScrollingCapture: NSObject, ObservableObject, NSWindowDelegate {
    @Published var frames: [NSImage] = []
    @Published var status = L("滚动页面后，点击「添加当前画面」。相邻画面应保留约一半重叠。")
    @Published var automatic = false
    @Published var busy = false
    @Published var horizontal = false
    private var selection: CaptureSelection?
    private var window: NSWindow?
    private var lastDigest: Data?
    private var cancelled = false
    private var targetApplication:NSRunningApplication?
    private var targetWindowID:CGWindowID?
    private var sessionID = UUID()
    private var automaticRunID = UUID()
    private var automaticTask:Task<Void,Never>?
    var finished: ((NSImage) -> Void)?
    var onClose:(()->Void)?
    var isActive:Bool { window?.isVisible == true }

    func start(selection: CaptureSelection, finished: @escaping (NSImage) -> Void) {
        stopAutomatic();sessionID = UUID();busy = false
        self.selection = selection; self.finished = finished; frames = []; lastDigest = nil; cancelled = false
        let point = CGPoint(x:selection.globalFrame.midX,y:NSScreen.screens.first!.frame.height-selection.globalFrame.midY)
        let targetWindow = selection.target.windows.first(where:{$0.frame.contains(point)})
        targetWindowID = targetWindow?.windowID
        targetApplication = targetWindow?.owningApplication.flatMap { NSRunningApplication(processIdentifier:$0.processID) }
        let window = NSPanel(contentRect: CGRect(x: selection.target.screen.frame.midX - 255, y: selection.target.screen.frame.maxY - 170, width: 510,height: 125), styleMask: [.titled,.closable,.utilityWindow], backing: .buffered, defer: false)
        window.title = L("长截图"); window.level = .floating; window.hidesOnDeactivate = false
        window.delegate = self
        window.isReleasedWhenClosed = false
        let center = CGPoint(x:selection.globalFrame.midX,y:selection.globalFrame.midY)
        if window.frame.contains(center) {
            let screen = selection.target.screen.visibleFrame
            for origin in [CGPoint(x:screen.minX+12,y:screen.minY+12),CGPoint(x:screen.maxX-window.frame.width-12,y:screen.minY+12)] {
                if !CGRect(origin:origin,size:window.frame.size).contains(center) { window.setFrameOrigin(origin);break }
            }
        }
        window.contentView = NSHostingView(rootView: ScrollingCaptureView(model: self))
        self.window = window; window.makeKeyAndOrderFront(nil)
        Task { await addFrame() }
    }
    func addFrame() async {
        guard !busy, !cancelled, let selection else { return }
        let expectedSession = sessionID
        busy = true; defer { if sessionID == expectedSession { busy = false } }
        do {
            if targetApplication?.isTerminated == true {
                throw NSError(domain:"ScreenshotKing",code:6,userInfo:[NSLocalizedDescriptionKey:L("目标应用已退出，请重新选择长截图区域。")])
            }
            if let targetApplication, !targetApplication.isTerminated { targetApplication.activate(options:[]) }
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard sessionID == expectedSession, !cancelled, !Task.isCancelled else { return }
            let filter:SCContentFilter
            if let targetWindowID {
                guard let targetWindow = content.windows.first(where:{$0.windowID == targetWindowID}) else {
                    throw NSError(domain:"ScreenshotKing",code:7,userInfo:[NSLocalizedDescriptionKey:L("目标窗口已关闭或不再显示，已停止长截图。")])
                }
                filter = SCContentFilter(display:selection.target.display,including:[targetWindow])
            } else {
                let own = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
                filter = SCContentFilter(display: selection.target.display, excludingWindows: own)
            }
            let config = SCStreamConfiguration()
            config.sourceRect = selection.sourceRect
            config.width = Int(selection.rect.width * selection.target.screen.backingScaleFactor)
            config.height = Int(selection.rect.height * selection.target.screen.backingScaleFactor)
            config.showsCursor = false
            let cg = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard sessionID == expectedSession, !cancelled, !Task.isCancelled else { return }
            let image = NSImage(cgImage: cg, size: selection.rect.size)
            guard let tiff = image.tiffRepresentation else { throw NSError(domain: "ScreenshotKing", code: 1, userInfo: [NSLocalizedDescriptionKey:L("无法读取长截图帧")])}
            let hash = Data(SHA256.hash(data: tiff))
            if hash == lastDigest {
                status = L("画面未变化，未重复添加。"); automatic = false
            } else {
                frames.append(image); lastDigest = hash
                status = LF("%@ · 已捕获 %ld 帧 · %ld × %ld px", targetApplication?.localizedName ?? L("屏幕区域"), frames.count, config.width, config.height)
            }
            if frames.count >= 30 { automatic = false; status = L("已达到 30 帧上限，请完成当前长截图。") }
        } catch {
            guard sessionID == expectedSession, !cancelled, !Task.isCancelled else { return }
            stopAutomatic();status = LF("捕获失败：%@", error.localizedDescription)
        }
    }
    func autoScroll() {
        if automatic { stopAutomatic();return }
        guard AXIsProcessTrusted(), let selection else {
            status = L("自动滚动需要辅助功能权限。你仍可手动滚动，并添加当前画面。"); return
        }
        guard let targetApplication, !targetApplication.isTerminated else {
            status = L("请选择可滚动窗口内的区域后重新开始。");return
        }
        automatic = true
        let runID = UUID();automaticRunID = runID
        let expectedSession = sessionID
        automaticTask = Task {
            defer { if automaticRunID == runID { automatic = false;automaticTask = nil } }
            while automatic && !cancelled && sessionID == expectedSession && automaticRunID == runID && !Task.isCancelled {
                guard !targetApplication.isTerminated else { automatic = false;status = L("目标应用已退出，已停止自动滚动。");break }
                targetApplication.activate(options:[])
                do { try await Task.sleep(for:.milliseconds(120)) } catch { break }
                guard automatic, sessionID == expectedSession, automaticRunID == runID, !Task.isCancelled else { break }
                let point = CGPoint(x:selection.globalFrame.midX,y:NSScreen.screens.first!.frame.height-selection.globalFrame.midY)
                guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else {
                    automatic = false;status = L("无法检查目标窗口位置，已暂停自动滚动。");break
                }
                let frontWindow = windowInfo.first(where:{ info in
                          guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                                layer >= 0, layer <= NSWindow.Level.floating.rawValue,
                                (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                                let bounds = info[kCGWindowBounds as String] as? [String:Any],
                                let frame = CGRect(dictionaryRepresentation:bounds as CFDictionary) else { return false }
                          return frame.contains(point)
                      })
                guard (frontWindow?[kCGWindowNumber as String] as? NSNumber)?.uint32Value == targetWindowID else {
                    let owner = frontWindow?[kCGWindowOwnerName as String] as? String ?? L("未知窗口")
                    automatic = false;status = LF("选区被%@遮挡，请移开遮挡窗口后继续自动滚动。", owner);break
                }
                let movement = Int32((horizontal ? selection.rect.width : selection.rect.height) * 0.45)
                let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
                                    wheel1: horizontal ? 0 : -movement, wheel2: horizontal ? -movement : 0, wheel3: 0)
                // WindowServer must annotate a newly created event with its target window.
                // A raw scroll sent straight to a PID has no AppKit window number.
                CGEvent(mouseEventSource:nil,mouseType:.mouseMoved,mouseCursorPosition:point,mouseButton:.left)?.post(tap:.cghidEventTap)
                event?.location = point
                event?.post(tap:.cghidEventTap)
                do { try await Task.sleep(for: .milliseconds(750)) } catch { break }
                if automatic && sessionID == expectedSession && automaticRunID == runID && !Task.isCancelled { await addFrame() }
            }
        }
    }
    private func stopAutomatic() {
        automatic = false;automaticRunID = UUID();automaticTask?.cancel();automaticTask = nil
    }
    func finish() {
        stopAutomatic()
        do {
            let image = try ImageProcessing.stitch(images: frames, direction: horizontal ? .horizontal : .vertical)
            let completion = finished;window?.close();completion?(image)
        } catch { status = LF("拼接失败：%@", error.localizedDescription) }
    }
    func cancel() { stopAutomatic(); cancelled = true; window?.close(); frames = [] }
    func windowWillClose(_ notification:Notification) {
        guard notification.object as? NSWindow === window else { return }
        stopAutomatic();sessionID = UUID();cancelled = true;busy = false;targetApplication = nil;targetWindowID = nil;finished = nil;selection = nil;frames = []
        let closed = onClose;onClose = nil;closed?()
    }
}

private struct ScrollingCaptureView: View {
    @ObservedObject var model: ScrollingCapture
    var body: some View {
        VStack(alignment: .leading,spacing: 12) {
            Text(model.status).font(.callout).lineLimit(3)
            HStack {
                Toggle(L("横向"),isOn:$model.horizontal).toggleStyle(.checkbox).disabled(!model.frames.isEmpty && model.automatic)
                Button(L("添加当前画面")) { Task { await model.addFrame() } }.disabled(model.busy || model.automatic)
                Button(model.automatic ? L("暂停滚动") : L("自动滚动")) { model.autoScroll() }.disabled(model.busy && !model.automatic)
                Spacer()
                Button(L("取消")) { model.cancel() }
                Button(L("完成拼接")) { model.finish() }.disabled(model.frames.isEmpty || model.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(16).frame(width: 570)
    }
}
