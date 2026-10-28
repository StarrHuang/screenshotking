import AppKit
import SwiftUI
import Carbon

@MainActor final class AppSettings: ObservableObject {
    @Published var captureDelay: Double { didSet { defaults.set(captureDelay, forKey: "captureDelay") } }
    @Published var guides: Bool { didSet { defaults.set(guides, forKey: "guides") } }
    @Published var outputAction: String { didSet { defaults.set(outputAction, forKey: "outputAction") } }
    @Published var saveToLibrary: Bool { didSet { defaults.set(saveToLibrary, forKey: "saveToLibrary") } }
    @Published var autoCopyCaptures: Bool { didSet { defaults.set(autoCopyCaptures, forKey: "autoCopyCaptures") } }
    @Published var systemAudio = false
    @Published var microphone = false
    @Published var camera = false
    @Published var silentRecording = false
    @Published var autoPasteMode:String { didSet { defaults.set(autoPasteMode,forKey:"autoPasteMode") } }
    @Published var autoPasteApps:String { didSet { defaults.set(autoPasteApps,forKey:"autoPasteApps") } }
    @Published var selectionToolbar: Bool { didSet { defaults.set(selectionToolbar, forKey: "selectionToolbar") } }
    @Published var recognition: String { didSet { defaults.set(recognition, forKey: "recognition") } }
    @Published var pinPlacement: String { didSet { defaults.set(pinPlacement, forKey: "pinPlacement") } }
    @Published var pinScope: Int { didSet { defaults.set(pinScope, forKey: "pinScope") } }
    @Published var shortcuts: [Shortcut] { didSet { defaults.set(try! JSONEncoder().encode(shortcuts), forKey: "shortcuts") } }
    let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["captureDelay": 0, "guides": false, "outputAction": "background", "saveToLibrary": true,"autoCopyCaptures":true,"selectionToolbar":false,"recognition":"window","pinPlacement":"original","pinScope":2,"autoPasteMode":"off","autoPasteApps":""])
        captureDelay = defaults.double(forKey: "captureDelay"); guides = defaults.bool(forKey: "guides")
        outputAction = defaults.string(forKey: "outputAction")!; saveToLibrary = defaults.bool(forKey: "saveToLibrary"); autoCopyCaptures = defaults.bool(forKey:"autoCopyCaptures")
        selectionToolbar = defaults.bool(forKey:"selectionToolbar"); recognition = defaults.string(forKey:"recognition")!
        pinPlacement = defaults.string(forKey:"pinPlacement")!; pinScope = defaults.integer(forKey:"pinScope")
        autoPasteMode = defaults.string(forKey:"autoPasteMode")!;autoPasteApps = defaults.string(forKey:"autoPasteApps")!
        if let data = defaults.data(forKey: "shortcuts") {
            do { shortcuts = try JSONDecoder().decode([Shortcut].self, from: data) }
            catch { shortcuts = Shortcut.defaults; NSLog("Shortcut settings could not be decoded: %@", error.localizedDescription) }
        } else { shortcuts = Shortcut.defaults }
    }
}

struct Shortcut: Codable, Identifiable, Equatable {
    var id: UInt32
    var label: String
    var keyCode: UInt32
    var modifiers: UInt32
    var enabled = true
    static var defaults: [Shortcut] {
        let mods = UInt32(cmdKey | optionKey | controlKey)
        return [Shortcut(id: 1,label: "区域 / 窗口截图",keyCode: 18,modifiers: mods),
                Shortcut(id: 2,label: "剪贴板历史",keyCode: 19,modifiers: mods),
                Shortcut(id: 3,label: "重复上次选区",keyCode: 20,modifiers: mods),
                Shortcut(id: 4,label: "长截图",keyCode: 21,modifiers: mods),
                Shortcut(id: 5,label: "开始 / 停止录屏",keyCode: 15,modifiers: mods)]
    }
    var display: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyNames[keyCode, default: "[\(keyCode)]"]
    }
    static let keyNames: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"+",25:"9",26:"7",27:"−",28:"8",29:"0",31:"O",32:"U",34:"I",35:"P",37:"L",38:"J",40:"K",45:"N",46:"M",49:"Space",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",118:"F4",120:"F2",122:"F1"]
}

@MainActor final class HotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var action: ((UInt32) -> Void)?
    private(set) var errors: [String] = []
    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            var key = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            if status == noErr, let userData {
                let owner = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { owner.action?(key.id) }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }
    func register(_ shortcuts: [Shortcut]) {
        refs.forEach { UnregisterEventHotKey($0) }; refs.removeAll(); errors.removeAll()
        for shortcut in shortcuts where shortcut.enabled {
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x534B4E47, id: shortcut.id), GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { refs.append(ref) }
            else { errors.append(LF("%@ %@ 注册失败（%ld），请换一组快捷键。", L(shortcut.label), shortcut.display, Int(status))) }
        }
    }
}

@MainActor struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    var applyShortcuts: () -> Void
    @State private var recordingID: UInt32?
    @State private var monitor: Any?
    var body: some View {
        TabView {
            ExportSettingsView().tabItem { Label(L("保存"),systemImage:"square.and.arrow.down") }
            Form {
                Picker(L("截图后"), selection: $settings.outputAction) {
                    Text(L("静默保存（稍后编辑）")).tag("background"); Text(L("打开编辑器")).tag("editor"); Text(L("复制到剪贴板")).tag("copy"); Text(L("钉在屏幕")).tag("pin"); Text(L("询问操作")).tag("ask")
                }
                Slider(value: $settings.captureDelay, in: 0...10, step: 1) { Text(LF("延迟 %ld 秒", Int(settings.captureDelay))) }
                Toggle(L("选区显示全屏坐标辅助线"), isOn: $settings.guides)
                Toggle(L("截图后自动复制"), isOn: $settings.autoCopyCaptures)
                Toggle(L("选区内直接标注（浮引方式）"),isOn:$settings.selectionToolbar)
                Picker(L("智能识别"),selection:$settings.recognition) {
                    Text(L("关闭功能")).tag("off"); Text(L("识别窗口")).tag("window");Text(L("识别界面元素（需要辅助功能权限）")).tag("element")
                }
                Toggle(L("截图保存到本地图片库"), isOn: $settings.saveToLibrary)
                Picker(L("钉图位置"),selection:$settings.pinPlacement) { Text(L("截图原位")).tag("original"); Text(L("屏幕中层叠")).tag("cascade") }
                Picker(L("钉图范围"),selection:$settings.pinScope) { Text(L("当前桌面")).tag(0);Text(L("当前桌面置顶")).tag(1);Text(L("所有桌面置顶")).tag(2) }
                Text(L("原生菜单栏工具 · 图片和剪贴板保存在这台 Mac。首次截图需要屏幕录制权限。"))
                    .font(.callout).foregroundStyle(.secondary)
                Button(L("打开屏幕录制权限设置")) { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
            }.padding(24).tabItem { Label(L("截图"), systemImage: "viewfinder") }
            Form {
                ForEach($settings.shortcuts) { $shortcut in
                    HStack {
                        Toggle(L(shortcut.label), isOn: $shortcut.enabled)
                        Spacer()
                        Button(recordingID == shortcut.id ? L("按下新快捷键…（Esc 取消）") : shortcut.display) { record(shortcut.id) }.monospaced()
                    }
                }
                Button(L("应用快捷键")) { applyShortcuts() }
                Text(L("默认使用 ⌃⌥⌘1–4，减少与已安装的截图工具冲突。注册冲突会明确报错。"))
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label(L("快捷键"), systemImage: "keyboard") }
            Form {
                Toggle(L("录制系统声音"), isOn: $settings.systemAudio)
                Toggle(L("录制麦克风"), isOn: $settings.microphone)
                Toggle(L("显示摄像头画面"), isOn: $settings.camera)
                Toggle(L("静默录屏（通过 ⌃⌥⌘R 或菜单栏停止）"),isOn:$settings.silentRecording)
                Text(L("音频和摄像头默认关闭。开始录制前选择区域，菜单栏可随时停止。录屏需要 macOS 15 或更新版本。"))
                    .font(.callout).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label(L("录屏"), systemImage: "record.circle") }
            Form {
                Picker(L("复制截图后自动粘贴"),selection:$settings.autoPasteMode) {
                    Text(L("关闭功能")).tag("off");Text(L("所有应用")).tag("all");Text(L("仅指定应用")).tag("selected")
                }
                if settings.autoPasteMode == "selected" { TextField(L("应用 Bundle ID（逗号分隔）"),text:$settings.autoPasteApps).textFieldStyle(.roundedBorder) }
                Text(L("需要辅助功能权限。仅向截图前使用的应用发送粘贴请求。关闭时只写入剪贴板。\n例如：com.apple.TextEdit, com.apple.Notes")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            }.padding(24).tabItem { Label(L("粘贴"),systemImage:"doc.on.clipboard") }
        }
        .frame(width: 650, height: 500)
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    }
    private func record(_ id: UInt32) {
        recordingID = id
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { recordingID = nil }
            else {
                var flags: UInt32 = 0
                if event.modifierFlags.contains(.command) { flags |= UInt32(cmdKey) }
                if event.modifierFlags.contains(.option) { flags |= UInt32(optionKey) }
                if event.modifierFlags.contains(.control) { flags |= UInt32(controlKey) }
                if event.modifierFlags.contains(.shift) { flags |= UInt32(shiftKey) }
                guard flags != 0 || event.keyCode >= 96 else { NSSound.beep(); return nil }
                if let index = settings.shortcuts.firstIndex(where: { $0.id == id }) {
                    settings.shortcuts[index].keyCode = UInt32(event.keyCode); settings.shortcuts[index].modifiers = flags
                }
                recordingID = nil
            }
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            return nil
        }
    }
}
