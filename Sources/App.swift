import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import ImageIO

@main
struct ScreenshotKingMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--diagnostics") {
            let data: [String:Any] = ["screenCaptureAuthorized":CGPreflightScreenCaptureAccess(),
                                      "accessibilityAuthorized":AXIsProcessTrusted(),
                                      "screenCount":NSScreen.screens.count,
                                      "bundleIdentifier":Bundle.main.bundleIdentifier ?? "unbundled"]
            print(String(data:try! JSONSerialization.data(withJSONObject:data,options:[.sortedKeys,.prettyPrinted]),encoding:.utf8)!)
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = AppSettings()
    let captureService = CaptureCoordinator()
    let clipboard = ClipboardStore()
    let library = CaptureLibrary()
    let hotkeys = HotkeyManager()
    let scrolling = ScrollingCapture()
    private var item: NSStatusItem!
    private var windows: [NSWindowController] = []
    private var editors: [ImageEditorController] = []
    private var pins: [PinController] = []
    private var clipboardWindow: ClipboardWindow?
    private var homeWindow: NSWindowController?
    private var settingsWindow: NSWindowController?
    private var libraryWindow: NSWindowController?
    private var recorderStorage: AnyObject?
    private var subscriptions = Set<AnyCancellable>()
    private var isCapturing = false
    private var inlineEditor:InlineCaptureEditor?
    private var hiddenWindows:[NSWindow] = []
    private var lastCaptureImage:NSImage?
    private var lastCaptureDocumentURL:URL?
    private var lastCaptureOrigin:CGRect?
    private var longCaptureCompletedSilently = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName:"viewfinder",accessibilityDescription:"ScreenshotKing")
        item.button?.toolTip = "ScreenshotKing"
        buildMainMenu()
        buildMenu()
        hotkeys.action = { [weak self] id in
            switch id {
            case 1: self?.capture()
            case 2: self?.showClipboard()
            case 3: self?.repeatCapture()
            case 4: self?.longCapture()
            case 5: self?.recordScreen()
            default: break
            }
        }
        hotkeys.register(settings.shortcuts)
        clipboard.$isMonitoring.sink { [weak self] _ in DispatchQueue.main.async { self?.buildMenu() } }.store(in: &subscriptions)
        if CommandLine.arguments.contains("--open"), let index = CommandLine.arguments.firstIndex(of:"--open"), CommandLine.arguments.indices.contains(index+1) {
            openImage(URL(fileURLWithPath:CommandLine.arguments[index+1]))
        } else { showHome() }
        if !hotkeys.errors.isEmpty { alert(hotkeys.errors.joined(separator:"\n")) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if #available(macOS 15.0,*), let recorder = recorderStorage as? ScreenRecorder, recorder.isBusy {
            let alert = NSAlert(); alert.messageText = "录屏仍在进行"; alert.informativeText = "请先停止录屏并等待文件保存，再退出。"; alert.runModal(); return .terminateCancel
        }
        return .terminateNow
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) { filenames.forEach { openImage(URL(fileURLWithPath:$0)) } }
    func buildMenu() {
        guard item != nil else { return }
        let menu = NSMenu()
        func add(_ title: String,_ selector: Selector,_ key: String = "") {
            let entry = NSMenuItem(title:title,action:selector,keyEquivalent:key); entry.target = self; menu.addItem(entry)
        }
        add("区域 / 窗口截图",#selector(capture)); add("截取整个屏幕",#selector(fullCapture)); add("重复上次选区",#selector(repeatCapture))
        add("长截图…",#selector(longCapture)); add("录屏…",#selector(recordScreen))
        if #available(macOS 15.0,*), let recorder = recorderStorage as? ScreenRecorder, recorder.isRecording { add("⏹ 停止录屏并保存",#selector(stopRecording)) }
        menu.addItem(.separator())
        add("剪贴板历史",#selector(showClipboard)); add(clipboard.isMonitoring ? "暂停剪贴板监听" : "开启剪贴板监听",#selector(toggleClipboard))
        add("打开图片…",#selector(openFile)); add("编辑最近截图",#selector(editRecentCapture)); add("编辑剪贴板图片",#selector(openClipboardImage)); add("截图库",#selector(showLibrary))
        menu.addItem(.separator()); add("显示所有钉图",#selector(showPins)); add("隐藏所有钉图",#selector(hidePins)); add("关闭所有钉图",#selector(closePins))
        menu.addItem(.separator()); add("ScreenshotKing",#selector(showHome)); add("设置…",#selector(showSettings),","); add("退出",#selector(quit),"q")
        item.menu = menu
    }
    private func buildMainMenu() {
        let root = NSMenu()
        func submenu(_ title:String)->NSMenu {
            let item = NSMenuItem(title:title,action:nil,keyEquivalent:"");let menu = NSMenu(title:title);item.submenu = menu;root.addItem(item);return menu
        }
        let appMenu = submenu("ScreenshotKing")
        let preferences = NSMenuItem(title:"设置…",action:#selector(showSettings),keyEquivalent:",");preferences.target = self;appMenu.addItem(preferences)
        appMenu.addItem(.separator());let quit = NSMenuItem(title:"退出 ScreenshotKing",action:#selector(quit),keyEquivalent:"q");quit.target = self;appMenu.addItem(quit)
        let file = submenu("文件")
        for (title,selector) in [("区域 / 窗口截图",#selector(capture)),("截取整个屏幕",#selector(fullCapture)),("重复上次选区",#selector(repeatCapture)),("长截图…",#selector(longCapture)),("录屏…",#selector(recordScreen))] {
            let entry = NSMenuItem(title:title,action:selector,keyEquivalent:"");entry.target = self;file.addItem(entry)
        }
        file.addItem(.separator())
        let recent = NSMenuItem(title:"编辑最近截图",action:#selector(editRecentCapture),keyEquivalent:"");recent.target = self;file.addItem(recent)
        for (title,selector,key) in [("打开图片…",#selector(openFile),"o"),("截图库",#selector(showLibrary),"l")] {
            let entry = NSMenuItem(title:title,action:selector,keyEquivalent:key);entry.target = self;file.addItem(entry)
        }
        let edit = submenu("编辑")
        for (title,selector,key) in [("撤销",Selector(("undo:")),"z"),("重做",Selector(("redo:")),"Z"),("剪切",#selector(NSText.cut(_:)),"x"),("复制",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")] {
            edit.addItem(NSMenuItem(title:title,action:selector,keyEquivalent:key))
        }
        NSApp.mainMenu = root
    }
    @objc func capture() { choose(keepHiddenAfterSelection:settings.outputAction == "background") { [weak self] selection in self?.receivedSelection(selection) } }
    @objc func repeatCapture() { choose(reuse:true,keepHiddenAfterSelection:settings.outputAction == "background") { [weak self] selection in self?.receivedSelection(selection) } }
    @objc func fullCapture() {
        guard ensureCapturePermission(),!isCapturing,!scrolling.isActive else { return }
        hideOwnWindows(); isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let targets = try await captureService.targets()
                let target = targets.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) ?? targets.first
                if let target {
                    receive(NSImage(cgImage:target.image,size:target.screen.frame.size))
                    if settings.outputAction != "background" { restoreOwnWindows() }
                } else { restoreOwnWindows() }
            } catch { restoreOwnWindows();show(error) }
        }
    }
    @objc func longCapture() {
        choose(restoreAfterSelection:false) { [weak self] selection in
            guard let self else { return }
            longCaptureCompletedSilently = false
            scrolling.onClose = { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.longCaptureCompletedSilently { self.discardHiddenWindows() }
                    else { self.restoreOwnWindows() }
                    self.longCaptureCompletedSilently = false
                }
            }
            scrolling.start(selection:selection) { [weak self] image in
                guard let self else { return }
                self.receive(image)
                if self.settings.outputAction == "background" { self.longCaptureCompletedSilently = true }
            }
        }
    }
    private func choose(reuse: Bool = false, restoreAfterSelection:Bool = true, keepHiddenAfterSelection:Bool = false, action: @escaping (CaptureSelection) -> Void) {
        guard ensureCapturePermission(),!isCapturing,!scrolling.isActive else { return }
        clipboard.rememberFrontmostApplication()
        isCapturing = true; hideOwnWindows()
        Task {
            if settings.captureDelay > 0 { try? await Task.sleep(for:.seconds(settings.captureDelay)) }
            captureService.choose(reuseLast:reuse,guides:settings.guides,recognition:settings.recognition) { [weak self] result in
                self?.isCapturing = false
                switch result {
                case .success(let selection):
                    if let selection {
                        if restoreAfterSelection {
                            if !(keepHiddenAfterSelection && self?.settings.outputAction == "background") { self?.restoreOwnWindows() }
                        }
                        action(selection)
                    } else { self?.restoreOwnWindows() }
                case .failure(let error): self?.restoreOwnWindows();self?.show(error)
                }
            }
        }
    }
    private func ensureCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let granted = CGRequestScreenCaptureAccess()
        if !granted { alert("macOS 尚未授权当前 ScreenshotKing 截图。请在系统设置 → 隐私与安全性 → 录屏与系统录音中允许此应用并重新打开。\n\n如果开关已经开启，请移除旧记录后重新添加当前应用：\n\(Bundle.main.bundlePath)") }
        return granted
    }
    private func hideOwnWindows() {
        hiddenWindows = NSApp.windows.filter { $0.isVisible }
        hiddenWindows.forEach { $0.orderOut(nil) }
    }
    private func restoreOwnWindows() { hiddenWindows.forEach { $0.orderFront(nil) };hiddenWindows.removeAll() }
    private func discardHiddenWindows() { hiddenWindows.removeAll() }
    private func receivedSelection(_ selection:CaptureSelection) {
        guard let image = selection.image else { restoreOwnWindows();alert("无法读取截图。");return }
        if settings.outputAction == "background" { receive(image,origin:selection.globalFrame);return }
        if settings.selectionToolbar {
            if settings.autoCopyCaptures { copyImageToPasteboard(image) }
            var documentURL:URL?
            if settings.saveToLibrary { do { documentURL = try library.add(image) } catch { show(error) } }
            let editor = InlineCaptureEditor(selection:selection,documentURL:documentURL,onPin:{ [weak self] in self?.pin($0,frame:selection.globalFrame) },onCopy:{ [weak self] in self?.copyImageAndMaybePaste($0) })
            editor.onClose = { [weak self] in self?.inlineEditor = nil }
            inlineEditor = editor;editor.show()
        } else { receive(image,origin:selection.globalFrame) }
    }
    private func receive(_ image: NSImage?,origin:CGRect? = nil,forceEdit:Bool = false) {
        guard let image else { alert("无法读取所选区域的图像。"); return }
        // The configured copy action already writes the completed capture and may also paste it.
        // For other output actions, auto-copy only updates the pasteboard and never sends keystrokes.
        if settings.autoCopyCaptures && (forceEdit || settings.outputAction != "copy") {
            copyImageToPasteboard(image)
        }
        var documentURL: URL?
        if settings.saveToLibrary { do { documentURL = try library.add(image) } catch { show(error) } }
        if !forceEdit {
            lastCaptureImage = image;lastCaptureDocumentURL = documentURL;lastCaptureOrigin = origin
        }
        switch forceEdit ? "editor" : settings.outputAction {
        case "background":
            do {
                let url = try ScreenshotExport.save(image,defaults:settings.defaults,silently:true)
                if let url { settings.defaults.set(url.path,forKey:"lastCaptureExportPath") }
                discardHiddenWindows()
            } catch { restoreOwnWindows();show(error) }
        case "copy": copyImageAndMaybePaste(image)
        case "pin": pin(image,frame:origin)
        case "ask":
            let alert = NSAlert(); alert.messageText = "截图已完成"; alert.informativeText = "选择下一步操作。"
            ["标注","复制","钉图","取消"].forEach { alert.addButton(withTitle:$0) }
            switch alert.runModal() {
            case .alertFirstButtonReturn: edit(image, documentURL: documentURL,origin:origin)
            case .alertSecondButtonReturn: copyImageAndMaybePaste(image)
            case .alertThirdButtonReturn: pin(image,frame:origin)
            default: break
            }
        default: edit(image, documentURL: documentURL,origin:origin)
        }
    }
    func copyImageAndMaybePaste(_ image:NSImage) {
        guard copyImageToPasteboard(image) else { return }
        let apps = settings.autoPasteApps.split(separator:",").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
        if settings.autoPasteMode == "all" || settings.autoPasteMode == "selected" && apps.contains(clipboard.previousApplicationBundleIdentifier ?? "") {
            let result = clipboard.requestPasteIntoPreviousApplication()
            if result == .copiedPermissionRequired { alert("截图已复制。自动粘贴需要辅助功能权限。"); }
        }
    }
    @discardableResult private func copyImageToPasteboard(_ image:NSImage) -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([image]) else { alert("无法写入剪贴板。");return false }
        return true
    }
    func edit(_ image: NSImage, documentURL: URL? = nil,origin:CGRect? = nil) {
        let editor = ImageEditorController(image:image,documentURL:documentURL,onCopy:{ [weak self] in self?.copyImageAndMaybePaste($0) }) { [weak self] image in self?.pin(image,frame:origin) }
        editor.onClose = { [weak self,weak editor] in self?.editors.removeAll { $0 === editor } }
        editors.append(editor); editor.show()
    }
    func pin(_ image: NSImage,frame:CGRect? = nil) {
        let desiredFrame = settings.pinPlacement == "original" ? frame : nil
        let pin = PinController(image:image,frame:desiredFrame,scope:settings.pinScope) { [weak self] image in self?.edit(image) }
        pin.onClose = { [weak self,weak pin] in self?.pins.removeAll { $0 === pin } }
        pins.append(pin); pin.show()
    }
    @objc func showPins() { pins.forEach { $0.show() } }
    @objc func hidePins() { pins.forEach { $0.window?.orderOut(nil) } }
    @objc func closePins() { pins.forEach { $0.close() }; pins.removeAll() }
    @objc func showClipboard() {
        clipboard.rememberFrontmostApplication()
        if clipboardWindow == nil { clipboardWindow = ClipboardWindow(store:clipboard,onPin:{ [weak self] in self?.pin($0) }) }
        clipboardWindow?.show()
    }
    @objc func toggleClipboard() { clipboard.isMonitoring ? clipboard.stopMonitoring() : clipboard.startMonitoring(); buildMenu() }
    @objc func openFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { panel.urls.forEach(openImage) }
    }
    private func openImage(_ url: URL) {
        guard let image = NSImage(contentsOf:url) else { alert("无法打开图片：\(url.lastPathComponent)"); return }
        edit(image)
    }
    @objc func openClipboardImage() {
        guard let image = NSImage(pasteboard:.general) else { alert("剪贴板中没有图片。"); return }; edit(image)
    }
    @objc func showLibrary() {
        if libraryWindow == nil {
            libraryWindow = host(title:"截图库",view:LibraryView(library:library) { [weak self] image, url in self?.edit(image, documentURL: url) })
        }
        library.reload(); activate(libraryWindow!)
    }
    @objc func editRecentCapture() {
        if let image = lastCaptureImage {
            edit(image,documentURL:lastCaptureDocumentURL,origin:lastCaptureOrigin)
            return
        }
        if let path = settings.defaults.string(forKey:"lastCaptureExportPath"), let image = NSImage(contentsOfFile:path) {
            edit(image)
            return
        }
        library.reload()
        if let entry = library.entries.first, let image = NSImage(contentsOf:entry.url) {
            edit(image,documentURL:entry.url.deletingPathExtension().appendingPathExtension("skedit"))
            return
        }
        alert("还没有可编辑的截图。")
    }
    @objc func showSettings() {
        if settingsWindow == nil {
            settingsWindow = host(title:"ScreenshotKing 设置",view:SettingsView(settings:settings) { [weak self] in
                guard let self else { return }; hotkeys.register(settings.shortcuts)
                if !hotkeys.errors.isEmpty { alert(hotkeys.errors.joined(separator:"\n")) }
            })
        }
        activate(settingsWindow!)
    }
    @objc func showHome() {
        if homeWindow == nil {
            homeWindow = host(title:"ScreenshotKing",view:HomeView(capture:{ [weak self] in self?.capture() },openImage:{ [weak self] in self?.openFile() },clipboard:{ [weak self] in self?.showClipboard() },library:{ [weak self] in self?.showLibrary() },settings:{ [weak self] in self?.showSettings() }))
        }
        activate(homeWindow!)
    }
    @objc func recordScreen() {
        guard !scrolling.isActive else { return }
        guard #available(macOS 15.0,*) else { alert("录屏需要 macOS 15 或更新版本。"); return }
        if let recorder = recorderStorage as? ScreenRecorder, recorder.isBusy { if recorder.isRecording { stopRecording() }; return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.mpeg4Movie]; panel.nameFieldStringValue = "ScreenshotKing_\(Int(Date().timeIntervalSince1970)).mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        choose { [weak self] selection in
            guard let self else { return }
            let recorder = ScreenRecorder(); self.recorderStorage = recorder
            recorder.changed = { [weak self] in self?.buildMenu() }
            Task {
                do { try await recorder.start(selection:selection,url:url,systemAudio:self.settings.systemAudio,microphone:self.settings.microphone,camera:self.settings.camera,silent:self.settings.silentRecording) }
                catch { self.show(error) }
            }
        }
    }
    @objc func stopRecording() { if #available(macOS 15.0,*), let recorder = recorderStorage as? ScreenRecorder { recorder.stop() } }
    @objc func quit() { NSApp.terminate(nil) }
    func show(_ error: Error) { NSApp.activate(ignoringOtherApps:true); NSAlert(error:error).runModal() }
    func alert(_ message: String) { let alert = NSAlert(); alert.messageText = "ScreenshotKing"; alert.informativeText = message; NSApp.activate(ignoringOtherApps:true); alert.runModal() }
    private func host<Content:View>(title:String,view:Content) -> NSWindowController {
        let window = NSWindow(contentViewController:NSHostingController(rootView:view)); window.title = title
        window.styleMask = [.titled,.closable,.miniaturizable,.resizable]; window.isReleasedWhenClosed = false; window.center()
        return NSWindowController(window:window)
    }
    private func activate(_ controller:NSWindowController) { controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
}

private struct HomeView: View {
    let capture: () -> Void
    let openImage: () -> Void
    let clipboard: () -> Void
    let library: () -> Void
    let settings: () -> Void
    var body: some View {
        VStack(alignment:.leading,spacing:22) {
            HStack(alignment:.top) {
                Image(nsImage:NSApp.applicationIconImage).resizable().frame(width:44,height:44)
                VStack(alignment:.leading,spacing:5) {
                    Text("ScreenshotKing").font(.system(size:27,weight:.semibold))
                    Text("截图、标注、剪贴板。随手就好。").foregroundStyle(.secondary)
                }
            }
            Button(action:capture) { HStack { Label("截取区域或窗口",systemImage:"plus.viewfinder"); Spacer(); Text("⌃⌥⌘1").monospaced().foregroundStyle(.secondary) }.padding(8) }.buttonStyle(.borderedProminent).controlSize(.large)
            HStack(spacing:14) {
                Button(action:openImage) { Label("图片标注",systemImage:"pencil.tip.crop.circle") }
                Button(action:clipboard) { Label("剪贴板",systemImage:"clipboard") }
                Button(action:library) { Label("截图库",systemImage:"photo.on.rectangle") }
                Spacer(); Button(action:settings) { Image(systemName:"gearshape") }.help("设置")
            }.buttonStyle(.bordered).controlSize(.large)
            Divider()
            Text("常驻菜单栏，关闭窗口后继续可用。\n拖动框选，点击选窗口，回车完成，Esc 取消。\n剪贴板监听由你开启，内容保存在本机。").font(.callout).foregroundStyle(.secondary).lineSpacing(6).fixedSize(horizontal:false,vertical:true)
        }.padding(30).frame(width:440)
    }
}
