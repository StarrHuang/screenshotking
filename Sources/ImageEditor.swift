import AppKit
import SwiftUI
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

private struct StoredMark: Codable {
    let tool: String
    let points: [[Double]]
    let color: [Double]
    let width: Double
    let text: String
    let stepNumber: Int?
    let style: AnnotationStyle?

    init(_ mark: EditorMark) {
        tool = mark.tool.rawValue
        points = mark.points.map { [Double($0.x), Double($0.y)] }
        let c = mark.color.usingColorSpace(.deviceRGB) ?? .red
        color = [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        width = Double(mark.width); text = mark.text; stepNumber = mark.stepNumber; style = mark.style
    }

    func restore() throws -> EditorMark {
        guard let tool = ImageEditorTool(rawValue: tool), color.count == 4,
              points.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }), width.isFinite, width > 0,
              color.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw ImageEditorDocumentError.invalidDocument("A saved annotation has invalid fields.")
        }
        let restoredNumber = stepNumber ?? (tool == .step ? Int(text) : nil)
        let restoredText = tool == .step && stepNumber == nil && Int(text) != nil ? "" : text
        return EditorMark(tool: tool, points: points.map { CGPoint(x: $0[0], y: $0[1]) }, color: NSColor(srgbRed: color[0], green: color[1], blue: color[2], alpha: color[3]), width: width, text: restoredText, stepNumber: restoredNumber, style: style ?? AnnotationStyle())
    }
}

private struct StoredDocument: Codable {
    let version: Int
    let sourceSize: [Double]
    let workingSize: [Double]
    let sourceFilename: String
    let workingFilename: String
    let marks: [StoredMark]
    let style: ImageEditorExportStyle?
}

public struct ImageEditorExportStyle: Codable, Equatable {
    public var cornerRadius: Double
    public var shadow: Bool
    public var scaleToOneX: Bool
    public var shadowStrength: Double
    public var previewShadow: Bool

    public init(cornerRadius: Double = 0, shadow: Bool = false, scaleToOneX: Bool = false, shadowStrength: Double = 0.36, previewShadow: Bool = true) {
        self.cornerRadius = cornerRadius; self.shadow = shadow; self.scaleToOneX = scaleToOneX
        self.shadowStrength = shadowStrength; self.previewShadow = previewShadow
    }
    private enum CodingKeys: String, CodingKey { case cornerRadius, shadow, scaleToOneX, shadowStrength, previewShadow }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(cornerRadius: try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0,
                  shadow: try c.decodeIfPresent(Bool.self, forKey: .shadow) ?? false,
                  scaleToOneX: try c.decodeIfPresent(Bool.self, forKey: .scaleToOneX) ?? false,
                  shadowStrength: try c.decodeIfPresent(Double.self, forKey: .shadowStrength) ?? 0.36,
                  previewShadow: try c.decodeIfPresent(Bool.self, forKey: .previewShadow) ?? true)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cornerRadius, forKey: .cornerRadius); try c.encode(shadow, forKey: .shadow); try c.encode(scaleToOneX, forKey: .scaleToOneX)
        try c.encode(shadowStrength, forKey: .shadowStrength); try c.encode(previewShadow, forKey: .previewShadow)
    }
}

public struct ImageEditorDocumentState {
    public let sourceImage: NSImage
    public let workingImage: NSImage
    public let marks: [EditorMark]
    public let style: ImageEditorExportStyle
}

public enum ImageEditorDocumentError: Error, LocalizedError {
    case invalidDocument(String)
    case missingImage(URL)
    case cannotEncodeImage

    public var errorDescription: String? {
        switch self {
        case let .invalidDocument(message): return "The editing document is invalid: \(message)"
        case let .missingImage(url): return "The editing document is missing its image file: \(url.path)"
        case .cannotEncodeImage: return "An image could not be encoded while saving the editing document."
        }
    }
}

/// JSON edit document plus two PNG files; `.skedit` URLs use a package directory.
public enum ImageEditorDocument {
    public static func load(from url: URL) throws -> ImageEditorDocumentState {
        let jsonURL = documentURL(for: url)
        guard FileManager.default.fileExists(atPath: jsonURL.path) else { throw ImageEditorDocumentError.invalidDocument("document.json is missing.") }
        let stored = try JSONDecoder().decode(StoredDocument.self, from: Data(contentsOf: jsonURL))
        guard stored.version == 1 else { throw ImageEditorDocumentError.invalidDocument("Unsupported version \(stored.version).") }
        guard stored.sourceSize.count == 2, stored.workingSize.count == 2,
              stored.sourceSize.allSatisfy({ $0.isFinite && $0 > 0 }), stored.workingSize.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw ImageEditorDocumentError.invalidDocument("Saved image dimensions are invalid.")
        }
        guard URL(fileURLWithPath: stored.sourceFilename).lastPathComponent == stored.sourceFilename,
              URL(fileURLWithPath: stored.workingFilename).lastPathComponent == stored.workingFilename else {
            throw ImageEditorDocumentError.invalidDocument("Saved image file names are invalid.")
        }
        let directory = jsonURL.deletingLastPathComponent()
        let source = try loadImage(directory.appendingPathComponent(stored.sourceFilename), size: NSSize(width: stored.sourceSize[0], height: stored.sourceSize[1]))
        let working = try loadImage(directory.appendingPathComponent(stored.workingFilename), size: NSSize(width: stored.workingSize[0], height: stored.workingSize[1]))
        return ImageEditorDocumentState(sourceImage: source, workingImage: working, marks: try stored.marks.map { try $0.restore() }, style: stored.style ?? ImageEditorExportStyle())
    }

    public static func save(to url: URL, sourceImage: NSImage, workingImage: NSImage, marks: [EditorMark], style: ImageEditorExportStyle = ImageEditorExportStyle()) throws {
        let jsonURL = documentURL(for: url)
        try FileManager.default.createDirectory(at: jsonURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if url.pathExtension.lowercased() == "skedit" {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        let sourceData = try pngData(sourceImage)
        let workingData = try pngData(workingImage)
        let sourceName = assetName(for: sourceData, suffix: "source")
        let workingName = assetName(for: workingData, suffix: "working")
        let directory = jsonURL.deletingLastPathComponent()
        let sourceURL = directory.appendingPathComponent(sourceName), workingURL = directory.appendingPathComponent(workingName)
        if !FileManager.default.fileExists(atPath: sourceURL.path) { try sourceData.write(to: sourceURL, options: .atomic) }
        if !FileManager.default.fileExists(atPath: workingURL.path) { try workingData.write(to: workingURL, options: .atomic) }
        let data = try JSONEncoder().encode(StoredDocument(version: 1, sourceSize: [Double(sourceImage.size.width), Double(sourceImage.size.height)], workingSize: [Double(workingImage.size.width), Double(workingImage.size.height)], sourceFilename: sourceName, workingFilename: workingName, marks: marks.map(StoredMark.init), style: style))
        try data.write(to: jsonURL, options: .atomic)
    }

    public static func containsDocument(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func documentURL(for url: URL) -> URL {
        if url.pathExtension.lowercased() == "skedit" {
            return url.appendingPathComponent("document.json")
        }
        return url
    }

    private static func loadImage(_ url: URL, size: NSSize) throws -> NSImage {
        guard FileManager.default.fileExists(atPath: url.path) else { throw ImageEditorDocumentError.missingImage(url) }
        let data = try Data(contentsOf: url)
        guard let rep = NSBitmapImageRep(data: data), let cg = rep.cgImage else { throw ImageEditorDocumentError.invalidDocument("An image file could not be decoded.") }
        return NSImage(cgImage: cg, size: size)
    }

    private static func pngData(_ image: NSImage) throws -> Data {
        guard let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first ?? image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
              let data = rep.representation(using: .png, properties: [:]) else { throw ImageEditorDocumentError.cannotEncodeImage }
        return data
    }

    private static func assetName(for data: Data, suffix: String) -> String {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(digest).\(suffix).png"
    }
}

public enum ImageEditorTool: String, CaseIterable, Identifiable {
    case select = "Select", note = "Note", step = "Step", shape = "Shape"
    case arrow = "Arrow", text = "Text", highlight = "Highlight", pen = "Pen"
    case line = "Line", rectangle = "Rectangle", ellipse = "Ellipse", number = "Number"
    case mosaic = "Mosaic", blur = "Blur", crop = "Crop", sticker = "Sticker", magnifier = "Magnifier", watermark = "Watermark"
    public var id: String { rawValue }
    fileprivate var title: String {
        switch self {
        case .select: return "选择"
        case .arrow: return "箭头"
        case .line: return "直线"
        case .rectangle: return "矩形"
        case .ellipse: return "椭圆"
        case .pen: return "画笔"
        case .text: return "文字"
        case .number: return "编号"
        case .highlight: return "高亮"
        case .mosaic: return "马赛克"
        case .blur: return "模糊"
        case .crop: return "裁剪"
        case .note: return "备注气泡"
        case .sticker: return "贴纸"
        case .magnifier: return "放大镜"
        case .watermark: return "水印"
        case .step: return "步骤"
        case .shape: return "形状"
        }
    }
    fileprivate var symbol: String {
        switch self {
        case .select: return "cursorarrow"
        case .arrow: return "arrow.up.right"
        case .line: return "line.diagonal"
        case .rectangle: return "rectangle"
        case .ellipse: return "oval"
        case .pen: return "pencil.tip"
        case .text: return "textformat"
        case .number: return "number"
        case .highlight: return "highlighter"
        case .mosaic: return "square.grid.3x3.square"
        case .blur: return "drop.halffull"
        case .crop: return "crop.rotate"
        case .note: return "text.bubble"
        case .sticker: return "face.smiling"
        case .magnifier: return "magnifyingglass"
        case .watermark: return "signature"
        case .step: return "list.number"
        case .shape: return "pentagon"
        }
    }
    fileprivate var toolbarTitle: String {
        switch self {
        case .note: "备注"
        case .step: "步骤"
        case .shape: "形状"
        case .arrow: "箭头"
        case .text: "文字"
        case .highlight: "高亮"
        case .pen: "画笔"
        default: title
        }
    }
}

public enum ImageEditorPresentation: Equatable {
    case window
    case inline
}

public enum ImageEditorToolShortcuts {
    public static let userDefaultsKey = "imageEditorToolShortcuts"
    public static let defaults: [String: String] = [
        "Select": "v", "Note": "n", "Step": "s", "Shape": "r", "Arrow": "a", "Text": "t",
        "Highlight": "h", "Pen": "p", "Line": "l", "Rectangle": "q", "Ellipse": "e", "Number": "1",
        "Mosaic": "m", "Blur": "b", "Crop": "c", "Sticker": "k", "Magnifier": "g", "Watermark": "w"
    ]

    public static func load(from defaultsStore: UserDefaults = .standard) -> [String: String] {
        (defaultsStore.dictionary(forKey: userDefaultsKey) as? [String: String]) ?? defaults
    }

    public static func save(_ shortcuts: [String: String], to defaultsStore: UserDefaults = .standard) {
        defaultsStore.set(shortcuts, forKey: userDefaultsKey)
    }
}

public struct EditorMark {
    public var tool: ImageEditorTool
    public var points: [CGPoint]
    public var color: NSColor
    public var width: CGFloat
    public var text: String
    public var stepNumber: Int?
    public var style: AnnotationStyle

    public init(tool: ImageEditorTool, points: [CGPoint], color: NSColor, width: CGFloat, text: String = "", stepNumber: Int? = nil, style: AnnotationStyle = AnnotationStyle()) {
        self.tool = tool; self.points = points; self.color = color; self.width = width; self.text = text; self.stepNumber = stepNumber; self.style = style
    }
}

/// Opens a dedicated, independently-owned editor window for a captured image.
@MainActor
public final class ImageEditorController: NSObject, NSWindowDelegate {
    private let image: NSImage
    private let onPin: (NSImage) -> Void
    private let onCopy: ((NSImage) -> Void)?
    public let documentURL: URL?
    public var onClose: (() -> Void)?
    private var window: NSWindow?

    public init(image: NSImage, documentURL: URL? = nil, onCopy:((NSImage)->Void)? = nil, onPin: @escaping (NSImage) -> Void) {
        self.image = image
        self.documentURL = documentURL
        self.onPin = onPin
        self.onCopy = onCopy
        super.init()
    }

    public func show() {
        NSApp.setActivationPolicy(.regular)
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps:true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let state: ImageEditorDocumentState?
        do {
            if let documentURL, ImageEditorDocument.containsDocument(at: documentURL) { state = try ImageEditorDocument.load(from: documentURL) }
            else { state = nil }
        } catch { NSAlert(error: error).runModal(); return }
        let originalImage = state?.sourceImage ?? image
        let rootImage = state?.workingImage ?? image
        let initialStyle = state?.style ?? ImageEditorExportStyle()
        if state == nil, let documentURL {
            do { try ImageEditorDocument.save(to: documentURL, sourceImage: originalImage, workingImage: rootImage, marks: [], style: initialStyle) }
            catch { NSAlert(error: error).runModal(); return }
        }
        let saveDocument: (NSImage, [EditorMark], ImageEditorExportStyle) -> Void = { [documentURL] workingImage, marks, style in
            guard let documentURL else { return }
            do { try ImageEditorDocument.save(to: documentURL, sourceImage: originalImage, workingImage: workingImage, marks: marks, style: style) }
            catch { NSAlert(error: error).runModal() }
        }
        var closeEditor: (() -> Void)?
        let root = ImageEditorContent(image: rootImage, sourceImage: originalImage, initialMarks: state?.marks ?? [], initialStyle: initialStyle, hasDocumentURL: documentURL != nil, onPin: onPin, onCopy: onCopy, onDocumentChange: saveDocument, onClose: { closeEditor?() })
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 740), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        closeEditor = { [weak window] in window?.close() }
        window.title = "图片编辑"
        window.identifier = NSUserInterfaceItemIdentifier("screenshotking.editor")
        window.minSize = NSSize(width: 760, height: 520)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: root)
        window.center()
        NSApp.activate(ignoringOtherApps:true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    public func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === window else { return }
        closedWindow.delegate = nil
        closedWindow.contentView = nil
        window = nil
        onClose?()
        if !NSApp.windows.contains(where:{$0.isVisible && $0.identifier?.rawValue == "screenshotking.editor"}) { NSApp.setActivationPolicy(.accessory) }
    }
    public func windowShouldClose(_ sender:NSWindow)->Bool { sender.makeFirstResponder(nil);return true }
}

@MainActor private final class EditorCanvasHandle {
    weak var view: EditorCanvasView?
    func detach(_ candidate: EditorCanvasView) { if view === candidate { view = nil } }
}

@MainActor
public struct ImageEditorContent: View {
    public let presentation: ImageEditorPresentation
    public let inlineImageFrame: CGRect?
    let image: NSImage
    let sourceImage: NSImage
    let initialMarks: [EditorMark]
    let initialStyle: ImageEditorExportStyle
    let hasDocumentURL: Bool
    let onPin: (NSImage) -> Void
    let onCopy: ((NSImage) -> Void)?
    let onDocumentChange: (NSImage, [EditorMark], ImageEditorExportStyle) -> Void
    let onClose: () -> Void
    @State private var tool: ImageEditorTool = .arrow
    @State private var color: Color = Color(nsColor:AnnotationTheme.color)
    @State private var width: Double = 4
    @State private var zoomToFit = true
    @State private var revision = 0
    @State private var crop: CGRect?
    @State private var hex = "—"
    @State private var cornerRadius: Double
    @State private var dropShadow: Bool
    @State private var standard1x: Bool
    @State private var shadowStrength: Double
    @State private var previewShadow: Bool
    private let canvasHandle = EditorCanvasHandle()
    private var canvasRef: EditorCanvasView? { canvasHandle.view }
    @State private var showToolSettings = false
    @State private var showStickerPicker = false
    @AppStorage("editorToolOrder") private var toolOrderString = ImageEditorTool.allCases.map(\.rawValue).joined(separator:",")
    @AppStorage("editorHiddenTools") private var hiddenToolString = ""
    @AppStorage("defaultEditorTool") private var defaultToolString = ImageEditorTool.arrow.rawValue
    @State private var toolShortcutValues = ImageEditorToolShortcuts.load()
    @State private var loadErrorMessage: String?
    @State private var annotationStyle:AnnotationStyle = { var value = AnnotationStyle();value.colorPreset = .theme;value.followsThemeSize = true;return value }()
    @State private var showAnnotationInspector = false

    private var toolUsageHint: String {
        switch tool {
        case .note, .text: "点击图片输入文字，回车完成，双击修改"
        case .step: "点击或拖出步骤位置，输入说明，回车完成"
        case .select: "点击选择标注，拖动移动；双击文字编辑"
        default: "拖动添加标注"
        }
    }

    public init(image: NSImage, documentURL: URL? = nil, presentation: ImageEditorPresentation = .window, inlineImageFrame: CGRect? = nil, onPin: @escaping (NSImage) -> Void, onCopy: ((NSImage) -> Void)? = nil, onClose: @escaping () -> Void = {}) {
        var loaded: ImageEditorDocumentState?
        var loadError: String?
        do {
            if let documentURL, ImageEditorDocument.containsDocument(at: documentURL) { loaded = try ImageEditorDocument.load(from: documentURL) }
            else { loaded = nil }
        } catch {
            loaded = nil
            loadError = error.localizedDescription
        }
        let source = loaded?.sourceImage ?? image
        let working = loaded?.workingImage ?? image
        let style = loaded?.style ?? ImageEditorExportStyle()
        let save: (NSImage, [EditorMark], ImageEditorExportStyle) -> Void = { [documentURL] workingImage, marks, exportStyle in
            guard let documentURL else { return }
            do { try ImageEditorDocument.save(to: documentURL, sourceImage: source, workingImage: workingImage, marks: marks, style: exportStyle) }
            catch { NSAlert(error: error).runModal() }
        }
        if loaded == nil, loadError == nil, let documentURL {
            do { try ImageEditorDocument.save(to: documentURL, sourceImage: source, workingImage: working, marks: [], style: style) }
            catch { loadError = error.localizedDescription }
        }
        self.image = working
        self.presentation = presentation
        self.inlineImageFrame = inlineImageFrame
        self.sourceImage = source
        self.initialMarks = loaded?.marks ?? []
        self.initialStyle = style
        self.hasDocumentURL = documentURL != nil
        self.onPin = onPin
        self.onCopy = onCopy
        self.onDocumentChange = save
        self.onClose = onClose
        _cornerRadius = State(initialValue: style.cornerRadius)
        _dropShadow = State(initialValue: style.shadow)
        _standard1x = State(initialValue: style.scaleToOneX)
        _shadowStrength = State(initialValue: style.shadowStrength)
        _previewShadow = State(initialValue: style.previewShadow)
        _tool = State(initialValue: ImageEditorTool(rawValue: UserDefaults.standard.string(forKey: "defaultEditorTool") ?? "arrow") ?? .arrow)
        _loadErrorMessage = State(initialValue: loadError)
    }

    init(image: NSImage, sourceImage: NSImage, initialMarks: [EditorMark], initialStyle: ImageEditorExportStyle, hasDocumentURL: Bool, presentation: ImageEditorPresentation = .window, inlineImageFrame: CGRect? = nil, onPin: @escaping (NSImage) -> Void, onCopy:((NSImage)->Void)?, onDocumentChange: @escaping (NSImage, [EditorMark], ImageEditorExportStyle) -> Void, onClose: @escaping () -> Void) {
        self.image = image
        self.presentation = presentation
        self.inlineImageFrame = inlineImageFrame
        self.sourceImage = sourceImage
        self.initialMarks = initialMarks
        self.initialStyle = initialStyle
        self.hasDocumentURL = hasDocumentURL
        self.onPin = onPin
        self.onCopy = onCopy
        self.onDocumentChange = onDocumentChange
        self.onClose = onClose
        _cornerRadius = State(initialValue: initialStyle.cornerRadius)
        _dropShadow = State(initialValue: initialStyle.shadow)
        _standard1x = State(initialValue: initialStyle.scaleToOneX)
        _shadowStrength = State(initialValue: initialStyle.shadowStrength)
        _previewShadow = State(initialValue: initialStyle.previewShadow)
        _tool = State(initialValue:ImageEditorTool(rawValue:UserDefaults.standard.string(forKey:"defaultEditorTool") ?? "arrow") ?? .arrow)
    }

    private var exportStyle: ImageEditorExportStyle {
        ImageEditorExportStyle(cornerRadius: cornerRadius, shadow: dropShadow, scaleToOneX: standard1x, shadowStrength: shadowStrength, previewShadow: previewShadow)
    }

    private var actionToolbar: some View {
        HStack(spacing:10) {
            Button { canvasRef?.undoLastEdit(); revision += 1 } label: { Image(systemName:"arrow.uturn.backward") }.help("撤销")
            Button { canvasRef?.redoLastEdit(); revision += 1 } label: { Image(systemName:"arrow.uturn.forward") }.help("重做")
            Menu("编辑") {
                Button("复制标注") { canvasRef?.duplicateSelectedMark() }
                Button("删除标注") { canvasRef?.deleteSelectedMark() }
                Button("应用裁剪") { applyCrop() }.disabled(crop == nil)
                Divider()
                Button("适应窗口") { zoomToFit = true }
                Button("原始像素") { zoomToFit = false }
                Button("工具栏布局…") { showToolSettings = true }
                Menu("扩展画布") {
                    Button("留白") { extendCanvas(theme:.white) }
                    Button("奶油色") { extendCanvas(theme:NSColor(calibratedRed:0.98,green:0.95,blue:0.88,alpha:1)) }
                    Button("浅灰") { extendCanvas(theme:NSColor(calibratedWhite:0.92,alpha:1)) }
                    Button("深色") { extendCanvas(theme:NSColor(calibratedWhite:0.12,alpha:1)) }
                }
            }
            Button("识别 / 翻译") { ImageIntelligence.show(image:renderedImage()) { replacement in canvasRef?.replaceImage(replacement) } }
            Spacer(minLength:8)
            Button("钉图") { onPin(renderedImage()) }
            Button("分享") { shareImage() }
            Button("复制") { copyImage() }.keyboardShortcut("c",modifiers:.command)
            Button("保存") { saveImage() }.keyboardShortcut("s",modifiers:.command)
            Button("关闭",action:onClose)
        }.padding(.horizontal,12).padding(.vertical,8)
    }

    private var annotationToolbar:some View {
        HStack(spacing:8) {
            ScrollView(.horizontal,showsIndicators:true) {
                HStack(spacing:7) {
                    ForEach(orderedTools.filter { !hiddenToolString.split(separator:",").contains(Substring($0.rawValue)) }) { item in
                        Button {
                            tool = item
                            if item == .shape { annotationStyle.fontSize = 24 }
                            if item == .note || item == .step { annotationStyle.fontSize = 17 }
                            if item == .sticker { showStickerPicker = true }
                        } label: { Label(item.toolbarTitle,systemImage:item.symbol) }
                            .buttonStyle(.bordered).tint(tool == item ? .accentColor : nil).help(item.title)
                    }
                }.padding(.vertical,4)
            }
            Divider().frame(height:24)
            Button("样式参数") { showAnnotationInspector.toggle() }
                .popover(isPresented:$showAnnotationInspector) { AnnotationInspector(tool:tool,style:$annotationStyle,color:$color,width:$width,onThemeChanged:{canvasRef?.refreshTheme();revision += 1}) }
            ColorPicker("颜色",selection:Binding(get:{color},set:{color = $0;annotationStyle.colorPreset = .custom})).labelsHidden().frame(width:30)
            Menu("主题") {
                Menu("大小") { ForEach(AnnotationSize.allCases) { value in Button(value.title) { AnnotationTheme.size = value;annotationStyle.followsThemeSize = true;canvasRef?.refreshTheme();revision += 1 } } }
                Menu("颜色") { ForEach([AnnotationColorPreset.red,.green,.blue,.purple,.white,.black],id:\.self) { value in Button(value.title) { AnnotationTheme.color = value.color;annotationStyle.colorPreset = .theme;color = Color(nsColor:value.color);canvasRef?.refreshTheme();revision += 1 } } }
            }
            if tool == .sticker { Button("贴纸库") { showStickerPicker = true } }
        }.padding(.horizontal,10).frame(height:48)
    }

    private var canvasView: some View {
        EditorCanvas(image: image, marks: initialMarks, annotationStyle: annotationStyle, onDocumentChange: { updatedImage, updatedMarks in
            onDocumentChange(updatedImage, updatedMarks, exportStyle)
        }, onSelectionChanged: { mark in
            guard let mark else { return }
            annotationStyle = mark.style; color = Color(nsColor: mark.color); width = Double(mark.width)
        }, tool: tool, color: NSColor(color), strokeWidth: CGFloat(width), zoomToFit: zoomToFit, previewCornerRadius: CGFloat(cornerRadius), previewShadow: dropShadow && previewShadow, previewShadowStrength: CGFloat(shadowStrength), revision: $revision, crop: $crop, hex: $hex, canvasHandle: canvasHandle)
            .background(Color(nsColor: .windowBackgroundColor))
    }

    private var exportControls: some View {
        HStack(spacing: 12) {
            Text("圆角"); Slider(value: $cornerRadius, in: 0...40).frame(width: 110)
            Toggle("导出阴影", isOn: $dropShadow)
            Slider(value: $shadowStrength, in: 0.05...0.8).frame(width: 100).help("阴影强度")
            Toggle("预览阴影", isOn: $previewShadow)
            Toggle("按 1x 输出", isOn: $standard1x)
            Spacer()
        }.font(.caption).padding(.horizontal, 12).padding(.bottom, 7)
    }

    public var body: some View {
        Group {
            if presentation == .inline, let inlineImageFrame {
                GeometryReader { geometry in
                    let toolbarWidth = min(max(100, geometry.size.width - 24), max(980, inlineImageFrame.width))
                    let toolbarHeight: CGFloat = 100
                    let belowY = inlineImageFrame.maxY + 60 + toolbarHeight / 2
                    let aboveY = inlineImageFrame.minY - 60 - toolbarHeight / 2
                    let preferredY = belowY + toolbarHeight / 2 <= geometry.size.height - 10 ? belowY : aboveY
                    let toolbarY = min(max(preferredY, 55), max(55, geometry.size.height - 55))
                    let toolbarX = min(max(inlineImageFrame.midX, toolbarWidth / 2 + 12), max(toolbarWidth / 2 + 12, geometry.size.width - toolbarWidth / 2 - 12))
                    ZStack(alignment: .topLeading) {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        canvasView.frame(width: inlineImageFrame.width, height: inlineImageFrame.height).position(x: inlineImageFrame.midX, y: inlineImageFrame.midY)
                        VStack(spacing: 0) { actionToolbar; annotationToolbar }.frame(width: toolbarWidth).background(.regularMaterial).clipShape(RoundedRectangle(cornerRadius: 10)).position(x: toolbarX, y: toolbarY)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    actionToolbar; annotationToolbar; Divider(); canvasView
                    if presentation == .window {
                        HStack { Text("\(pixelWidth) × \(pixelHeight) 像素"); Spacer(); Text(hasDocumentURL ? "编辑源自动保存 · \(toolUsageHint)" : toolUsageHint) }.font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(.vertical, 6)
                    }
                    exportControls
                }
                .frame(minWidth: presentation == .window ? 760 : 0, minHeight: presentation == .window ? 520 : 0)
            }
        }
        .onChange(of: cornerRadius) { _, _ in persistStyle() }
        .onChange(of: dropShadow) { _, _ in persistStyle() }
        .onChange(of: shadowStrength) { _, _ in persistStyle() }
        .onChange(of: previewShadow) { _, _ in persistStyle() }
        .onChange(of: standard1x) { _, _ in persistStyle() }
        .onChange(of: annotationStyle) { _, newValue in canvasRef?.updateSelectedStyle(newValue); canvasRef?.markStyle = newValue }
        .onChange(of: color) { _, newValue in canvasRef?.updateSelectedColor(NSColor(newValue)) }
        .onChange(of: width) { _, newValue in canvasRef?.updateSelectedWidth(CGFloat(newValue)) }
        .sheet(isPresented:$showToolSettings) { toolSettings }
        .sheet(isPresented: $showStickerPicker) {
            StickerPicker { selection in
                annotationStyle.sticker = selection
                annotationStyle.stickerRotation = 0
                tool = .sticker
                showStickerPicker = false
            }
        }
        .alert("编辑文档无法读取", isPresented: Binding(get: { loadErrorMessage != nil }, set: { if !$0 { loadErrorMessage = nil } })) {
            Button("关闭", role: .cancel) { loadErrorMessage = nil; onClose() }
        } message: { Text(loadErrorMessage ?? "") }
    }

    private var orderedTools:[ImageEditorTool] {
        let saved = toolOrderString.split(separator:",").compactMap { ImageEditorTool(rawValue:String($0)) }
        var seen = Set<String>()
        return (saved + ImageEditorTool.allCases).filter { seen.insert($0.rawValue).inserted }
    }
    private var toolSettings:some View {
        VStack(alignment:.leading,spacing:12) {
            Text("工具栏布局").font(.headline)
            Text("本应用单键快捷键仅在画布聚焦时生效；Shift 与空格保留给等比和拖动画布。").font(.caption).foregroundStyle(.secondary)
            Picker("新截图默认工具",selection:$defaultToolString) { ForEach(ImageEditorTool.allCases) { Text($0.title).tag($0.rawValue) } }
            List {
                ForEach(orderedTools) { item in
                    HStack {
                        Toggle(item.title,isOn:Binding(get:{ !hiddenToolString.split(separator:",").contains(Substring(item.rawValue)) },set:{ visible in
                            var hidden = Set(hiddenToolString.split(separator:",").map(String.init));if visible { hidden.remove(item.rawValue) } else { hidden.insert(item.rawValue) };hiddenToolString = hidden.sorted().joined(separator:",")
                        }))
                        Spacer()
                        TextField("键",text:shortcutBinding(for:item)).frame(width:46).help("单个字母或数字；留空禁用")
                        Button { moveTool(item,by:-1) } label:{ Image(systemName:"chevron.up") }.help("上移")
                        Button { moveTool(item,by:1) } label:{ Image(systemName:"chevron.down") }.help("下移")
                    }
                }
            }
            HStack {
                Button("恢复默认布局") { toolOrderString = ImageEditorTool.allCases.map(\.rawValue).joined(separator:",");hiddenToolString = "" }
                Button("恢复默认快捷键") { toolShortcutValues = ImageEditorToolShortcuts.defaults;ImageEditorToolShortcuts.save(toolShortcutValues) }
                Spacer();Button("完成") { showToolSettings = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width:400,height:500)
    }
    private func moveTool(_ item:ImageEditorTool,by delta:Int) {
        var tools = orderedTools;let index = tools.firstIndex(of:item)!;let next = index+delta
        guard tools.indices.contains(next) else { return };tools.swapAt(index,next);toolOrderString = tools.map(\.rawValue).joined(separator:",")
    }
    private func shortcutBinding(for item:ImageEditorTool)->Binding<String> {
        Binding(get:{toolShortcutValues[item.rawValue] ?? ""},set:{ value in
            let key = String(value.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(1))
            if !key.isEmpty && toolShortcutValues.contains(where:{$0.key != item.rawValue && $0.value == key}) { return }
            toolShortcutValues[item.rawValue] = key
            ImageEditorToolShortcuts.save(toolShortcutValues)
        })
    }

    private var currentImage: NSImage { canvasRef?.imageForDocument ?? image }
    private var pixelWidth: Int { currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?.width ?? Int(currentImage.size.width) }
    private var pixelHeight: Int { currentImage.cgImage(forProposedRect: nil, context: nil, hints: nil)?.height ?? Int(currentImage.size.height) }
    private func persistStyle() { onDocumentChange(canvasRef?.imageForDocument ?? image, canvasRef?.annotationsForDocument ?? initialMarks, exportStyle) }
    private func renderedImage() -> NSImage { canvasRef?.renderedImage(cornerRadius: CGFloat(cornerRadius), shadow: dropShadow, scaleToOneX: standard1x) ?? image }
    private func copyImage() {
        if let onCopy { onCopy(renderedImage());return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([renderedImage()])
    }
    private func saveImage() {
        do { try ScreenshotExport.save(renderedImage()) } catch { showError(error) }
    }
    private func runOCR() {
        guard let cg = renderedImage().cgImage(forProposedRect: nil, context: nil, hints: nil) else { showError(ImageProcessingError.unreadableImage); return }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        do {
            try VNImageRequestHandler(cgImage: cg).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            let alert = NSAlert(); alert.messageText = "Recognized Text"
            let field = NSTextView(frame: NSRect(x: 0, y: 0, width: 460, height: 240)); field.string = text; field.isEditable = true
            alert.accessoryView = NSScrollView(frame: field.frame); (alert.accessoryView as? NSScrollView)?.documentView = field
            alert.addButton(withTitle: "复制文字"); alert.addButton(withTitle: "关闭")
            if alert.runModal() == .alertFirstButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
        } catch { showError(error) }
    }
    private func applyCrop() { canvasRef?.applyCrop(); crop = nil; revision += 1 }
    private func extendCanvas(theme: NSColor) {
        let alert = NSAlert(); alert.messageText = "扩展画布"
        let field = NSTextField(string: "40"); field.frame = NSRect(x: 0, y: 0, width: 100, height: 24); alert.accessoryView = field
        alert.informativeText = "输入四周增加的像素数。"
        alert.addButton(withTitle: "扩展"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn, let padding = Int(field.stringValue), padding > 0 else { return }
        canvasRef?.extendCanvas(padding: padding, color: theme)
        revision += 1
    }
    private func shareImage() {
        guard let canvasRef else { return }
        let picker = NSSharingServicePicker(items: [renderedImage()])
        picker.show(relativeTo: NSRect(x: canvasRef.bounds.midX, y: canvasRef.bounds.midY, width: 1, height: 1), of: canvasRef, preferredEdge: .minY)
    }
    private func showError(_ error: Error) { let alert = NSAlert(error: error); alert.runModal() }
}

private struct EditorCanvas: NSViewRepresentable {
    let image: NSImage
    let marks: [EditorMark]
    let annotationStyle: AnnotationStyle
    let onDocumentChange: (NSImage, [EditorMark]) -> Void
    let onSelectionChanged: (EditorMark?) -> Void
    let tool: ImageEditorTool
    let color: NSColor
    let strokeWidth: CGFloat
    let zoomToFit: Bool
    let previewCornerRadius: CGFloat
    let previewShadow: Bool
    let previewShadowStrength: CGFloat
    @Binding var revision: Int
    @Binding var crop: CGRect?
    @Binding var hex: String
    let canvasHandle: EditorCanvasHandle

    func makeNSView(context: Context) -> EditorCanvasView {
        let view = EditorCanvasView(image: image, marks: marks)
        context.coordinator.view = view
        canvasHandle.view = view
        return view
    }
    func updateNSView(_ view: EditorCanvasView, context: Context) {
        canvasHandle.view = view
        view.tool = tool; view.markColor = color; view.markWidth = strokeWidth; view.zoomToFit = zoomToFit; view.markStyle = annotationStyle
        view.previewCornerRadius = previewCornerRadius; view.previewShadow = previewShadow; view.previewShadowStrength = previewShadowStrength
        view.invalidatePreview()
        view.onChange = { bounds, colorHex in DispatchQueue.main.async { crop = bounds; hex = colorHex; revision += 1 } }
        view.onDocumentChanged = onDocumentChange
        view.onSelectionChanged = onSelectionChanged
        view.needsDisplay = true
    }
    static func dismantleNSView(_ view:EditorCanvasView,coordinator:Coordinator) {
        view.onChange = nil;view.onDocumentChanged = nil;view.onSelectionChanged = nil;view.invalidatePreview();view.undoManager?.removeAllActions()
        coordinator.handle?.detach(view)
    }
    final class Coordinator { weak var view: EditorCanvasView?; weak var handle: EditorCanvasHandle?; init(_ handle:EditorCanvasHandle) { self.handle = handle } }
    func makeCoordinator() -> Coordinator { Coordinator(canvasHandle) }
}

@MainActor public final class EditorCanvasView: NSView, NSTextFieldDelegate {
    private(set) var image: NSImage
    var tool: ImageEditorTool = .arrow {
        didSet {
            setAccessibilityLabel(accessibilityDescription)
            if oldValue != tool, let field = inlineEditor, draftMark != nil,
               field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                finishTextEditing(save: false)
            }
        }
    }
    var markColor: NSColor = .systemRed
    var markWidth: CGFloat = 4
    var markStyle = AnnotationStyle()
    var previewCornerRadius: CGFloat = 0
    var previewShadow = false
    var previewShadowStrength: CGFloat = 0.36
    var zoomToFit = true
    var onChange: ((CGRect?, String) -> Void)?
    var onDocumentChanged: ((NSImage, [EditorMark]) -> Void)?
    var onSelectionChanged: ((EditorMark?) -> Void)?
    private var marks: [EditorMark] = []
    private var currentPoints: [CGPoint] = []
    private var cropSelection: CGRect?
    private var cachedBaseComposite: NSImage?
    private var cachedPreviewComposite: NSImage?
    private var selectedIndex: Int?
    private var draggingIndex: Int?
    private var lastDragPoint: CGPoint?
    private var spacePanEnabled = false
    private var panningCanvas = false
    private var lastPanLocation: CGPoint?
    private var panOffset = CGPoint.zero
    private var dragUndoRegistered = false
    private var inlineEditor: NSTextField?
    private var editingIndex: Int?
    private var draftMark: EditorMark?
    private var copiedMark: EditorMark?
    private let shortcutDefaults:UserDefaults
    private let localUndoManager: UndoManager = {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }()
    public override var undoManager: UndoManager? { localUndoManager }
    private var editingUndoManager: UndoManager { localUndoManager }
    private var number = 1
    public override var isFlipped: Bool { true }
    public override var acceptsFirstResponder:Bool { true }
    public override func acceptsFirstMouse(for event:NSEvent?)->Bool { true }

    public init(image: NSImage, marks: [EditorMark] = [], shortcutDefaults:UserDefaults = .standard) { self.image = image; self.marks = marks;self.shortcutDefaults = shortcutDefaults; super.init(frame: .zero); wantsLayer = true;setAccessibilityElement(true);setAccessibilityRole(.button);setAccessibilityLabel(accessibilityDescription); number = (marks.compactMap { $0.tool == .step ? ($0.stepNumber ?? Int($0.text)) : ($0.tool == .number ? Int($0.text) : nil) }.max() ?? 0) + 1 }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unsupported") }
    private var accessibilityDescription: String {
        let creation = [.note, .step, .text].contains(tool) ? "，按下可在画布中心创建并编辑" : ""
        return "标注画布，当前工具：\(tool.toolbarTitle)\(creation)"
    }
    public override func accessibilityPerformPress() -> Bool {
        guard [.note, .step, .text].contains(tool), !bounds.isEmpty else { return false }
        if let inlineEditor {
            let editingTool = editingIndex.flatMap { marks.indices.contains($0) ? marks[$0].tool : nil } ?? draftMark?.tool
            if editingTool == tool {
                focusInlineEditor(selectAll: true)
                return true
            }
            let hasContent = !inlineEditor.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            finishTextEditing(save: hasContent)
        }
        activateEditorWindowForEditing()
        let point = toImage(CGPoint(x: bounds.midX, y: bounds.midY))
        if tool == .step {
            let label = stepLabelPoint(from: point, direction: markStyle.stepDirection)
            draftMark = EditorMark(tool: .step, points: [point, label], color: markColor, width: markWidth, stepNumber: number, style: markStyle)
        } else {
            draftMark = EditorMark(tool: tool, points: [point], color: markColor, width: markWidth, style: markStyle)
        }
        beginTextEditing(markIndex: nil)
        return inlineEditor != nil
    }
    private func activateEditorWindowForEditing() {
        guard let window, !window.isKeyWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    private var pixelSize: CGSize {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image.size }
        return CGSize(width: cg.width, height: cg.height)
    }
    private var fittedScale: CGFloat { min(bounds.width / max(1, pixelSize.width), bounds.height / max(1, pixelSize.height)) }
    private var scale: CGFloat { zoomToFit ? fittedScale : 1 }
    private var imageRect: CGRect {
        let size = CGSize(width: pixelSize.width * scale, height: pixelSize.height * scale)
        return CGRect(x: (bounds.width - size.width) / 2 + panOffset.x, y: (bounds.height - size.height) / 2 + panOffset.y, width: size.width, height: size.height)
    }
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let rect = imageRect
        let hasPreview = !currentPoints.isEmpty && tool != .crop && tool != .select
        let composite = compositedImage(includePreview: hasPreview)
        let drawContext = NSGraphicsContext.current!.cgContext
        drawContext.saveGState()
        let radius = min(previewCornerRadius * scale, min(rect.width, rect.height) / 2)
        let imagePath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if previewShadow {
            drawContext.saveGState(); drawContext.setShadow(offset: CGSize(width: 0, height: -4), blur: 12 * previewShadowStrength, color: NSColor.black.withAlphaComponent(previewShadowStrength).cgColor)
            drawContext.addPath(imagePath); drawContext.setFillColor(NSColor.black.cgColor); drawContext.fillPath(); drawContext.restoreGState()
        }
        drawContext.addPath(imagePath); drawContext.clip()
        composite.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        drawContext.restoreGState()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.saveGState()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: rect.minX, y: rect.minY); ctx.scaleBy(x: scale, y: scale)
        if let cropSelection {
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(2 / max(0.01, scale)); ctx.setLineDash(phase: 0, lengths: [6 / max(0.01, scale), 4 / max(0.01, scale)])
            ctx.stroke(cropSelection)
        }
        if let selectedIndex, marks.indices.contains(selectedIndex) {
            let bounds = markBounds(marks[selectedIndex]).insetBy(dx: -4 / max(0.01, scale), dy: -4 / max(0.01, scale))
            ctx.setStrokeColor(NSColor.controlAccentColor.cgColor); ctx.setLineWidth(1.5 / max(0.01, scale)); ctx.setLineDash(phase: 0, lengths: [4 / max(0.01, scale), 3 / max(0.01, scale)]); ctx.stroke(bounds)
        }
        ctx.restoreGState(); NSGraphicsContext.restoreGraphicsState()
    }
    private func compositedImage(includePreview: Bool) -> NSImage {
        if includePreview {
            if let cachedPreviewComposite { return cachedPreviewComposite }
            var previewMarks = marks
            previewMarks.append(EditorMark(tool: tool, points: currentPoints, color: markColor, width: markWidth, style: markStyle))
            let rendered = ImageEditorRenderer.render(image: image, marks: previewMarks)
            cachedPreviewComposite = rendered
            return rendered
        }
        if let cachedBaseComposite { return cachedBaseComposite }
        let rendered = ImageEditorRenderer.render(image: image, marks: marks)
        cachedBaseComposite = rendered
        return rendered
    }
    private func invalidateComposite() {
        cachedBaseComposite = nil
        cachedPreviewComposite = nil
    }
    public func refreshTheme() { invalidateComposite();needsDisplay = true }
    func invalidatePreview() { cachedPreviewComposite = nil }
    private func toImage(_ point: CGPoint) -> CGPoint {
        let rect = imageRect
        return CGPoint(x: min(pixelSize.width, max(0, (point.x - rect.minX) / scale)), y: min(pixelSize.height, max(0, (point.y - rect.minY) / scale)))
    }
    public override func mouseDown(with event: NSEvent) {
        if inlineEditor == nil { window?.makeFirstResponder(self) }
        if inlineEditor != nil { focusInlineEditor(); return }
        let localPoint = convert(event.locationInWindow, from: nil)
        if spacePanEnabled {
            panningCanvas = true;lastPanLocation = localPoint;return
        }
        let p = toImage(localPoint)
        if event.clickCount > 1, let index = hitTestMark(at: p), [.note, .step, .shape, .text, .number, .watermark].contains(marks[index].tool) {
            beginTextEditing(markIndex: index); return
        }
        if tool == .select {
            selectedIndex = hitTestMark(at: p)
            onSelectionChanged?(selectedIndex.map { marks[$0] })
            draggingIndex = selectedIndex
            lastDragPoint = p
            dragUndoRegistered = false
            needsDisplay = true
            return
        }
        if tool == .sticker, markStyle.sticker != nil {
            currentPoints = [p]; cachedPreviewComposite = nil; needsDisplay = true; return
        }
        if [.text, .note, .sticker, .watermark].contains(tool) {
            let initial = tool == .sticker ? (markStyle.sticker?.text ?? "⭐️") : ""
            draftMark = EditorMark(tool: tool, points: [p], color: markColor, width: markWidth, text: initial, style: markStyle)
            beginTextEditing(markIndex: nil); return
        }
        currentPoints = [p]
        cachedPreviewComposite = nil
        if tool == .number {
            append(EditorMark(tool: .number, points: [p], color: markColor, width: markWidth, text: "\(number)", style: markStyle)); number += 1; currentPoints = []; return
        }
        if tool == .step { needsDisplay = true; return }
        needsDisplay = true
    }
    public override func mouseDragged(with event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        if panningCanvas, let lastPanLocation {
            panOffset.x += localPoint.x - lastPanLocation.x;panOffset.y += localPoint.y - lastPanLocation.y
            self.lastPanLocation = localPoint;needsDisplay = true;return
        }
        let point = toImage(localPoint)
        if let draggingIndex, marks.indices.contains(draggingIndex), let lastDragPoint {
            if !dragUndoRegistered {
                editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping(); dragUndoRegistered = true
            }
            let delta = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
            marks[draggingIndex].points = marks[draggingIndex].points.map { CGPoint(x: $0.x + delta.x, y: $0.y + delta.y) }
            self.lastDragPoint = point; invalidateComposite(); needsDisplay = true; return
        }
        if tool == .sticker { if currentPoints.count == 1 { currentPoints.append(point) } else { currentPoints[1] = point } }
        else if tool == .pen || tool == .blur || (tool == .mosaic && markStyle.mosaicMode != .rectangle) { currentPoints.append(point) }
        else if currentPoints.count > 1 { currentPoints[1] = constrainedPoint(point, from:currentPoints[0], shift:event.modifierFlags.contains(.shift)) }
        else { currentPoints.append(constrainedPoint(point, from:currentPoints[0], shift:event.modifierFlags.contains(.shift))) }
        cachedPreviewComposite = nil
        onChange?(tool == .crop ? currentBounds() : nil, hexAt(point)); needsDisplay = true
    }
    public override func mouseUp(with event: NSEvent) {
        if panningCanvas { panningCanvas = false;lastPanLocation = nil;return }
        if draggingIndex != nil {
            draggingIndex = nil; lastDragPoint = nil; dragUndoRegistered = false
            onDocumentChanged?(image, marks); needsDisplay = true; return
        }
        guard !currentPoints.isEmpty else { return }
        let point = toImage(convert(event.locationInWindow, from: nil))
        let endPoint = currentPoints.first.map { constrainedPoint(point, from:$0, shift:event.modifierFlags.contains(.shift)) } ?? point
        if currentPoints.count == 1 { currentPoints.append(endPoint) } else { currentPoints[currentPoints.count - 1] = endPoint }
        if tool == .crop { cropSelection = currentBounds(); onChange?(cropSelection, hexAt(point)) }
        else if tool == .step {
            let anchor = currentPoints[0]
            var label = currentPoints.last ?? anchor
            if hypot(label.x - anchor.x, label.y - anchor.y) < 12 { label = stepLabelPoint(from:anchor,direction:markStyle.stepDirection) }
            draftMark = EditorMark(tool: .step, points: [anchor, label], color: markColor, width: markWidth, text: "", stepNumber: number, style: markStyle)
            beginTextEditing(markIndex: nil)
        }
        else if tool != .select { append(EditorMark(tool: tool, points: currentPoints, color: markColor, width: markWidth, style: markStyle)) }
        currentPoints = []; cachedPreviewComposite = nil; needsDisplay = true
    }
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 || event.charactersIgnoringModifiers == " " { spacePanEnabled = true;return }
        if inlineEditor == nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
           let key = event.charactersIgnoringModifiers?.lowercased(),
           let selectedToolName = ImageEditorToolShortcuts.load(from:shortcutDefaults).first(where: { $0.value.lowercased() == key })?.key,
           let selectedTool = ImageEditorTool(rawValue: selectedToolName) {
            tool = selectedTool;currentPoints = [];invalidatePreview();needsDisplay = true;return
        }
        if event.keyCode == 51 || event.keyCode == 117 { deleteSelectedMark(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" { copySelectedMark(); return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "v" { pasteCopiedMark(); return }
        super.keyDown(with: event)
    }
    public override func keyUp(with event:NSEvent) {
        if event.keyCode == 49 || event.charactersIgnoringModifiers == " " { spacePanEnabled = false;return }
        super.keyUp(with:event)
    }
    private func constrainedPoint(_ point:CGPoint,from origin:CGPoint,shift:Bool)->CGPoint {
        guard shift && [.shape,.rectangle,.ellipse].contains(tool) else { return point }
        let width = point.x-origin.x,height = point.y-origin.y
        let side = max(abs(width),abs(height))
        return CGPoint(x:origin.x+(width < 0 ? -side : side),y:origin.y+(height < 0 ? -side : side))
    }
    private func stepLabelPoint(from anchor:CGPoint,direction:AnnotationStepDirection,distance:CGFloat = 62)->CGPoint {
        switch direction {
        case .right:return CGPoint(x:anchor.x+distance,y:anchor.y)
        case .left:return CGPoint(x:anchor.x-distance,y:anchor.y)
        case .above:return CGPoint(x:anchor.x,y:anchor.y-distance)
        case .below:return CGPoint(x:anchor.x,y:anchor.y+distance)
        }
    }
    private func beginTextEditing(markIndex: Int?) {
        if let field = inlineEditor {
            let hasOwner = (editingIndex.map { marks.indices.contains($0) } ?? false) || draftMark != nil
            if hasOwner {
                focusInlineEditor()
                return
            }
            field.delegate = nil
            field.removeFromSuperview()
            inlineEditor = nil
            editingIndex = nil
        }
        let mark = markIndex.flatMap { marks.indices.contains($0) ? marks[$0] : nil } ?? draftMark
        guard let mark, let point = (mark.tool == .step ? mark.points.last : mark.points.first) else { return }
        let origin = CGPoint(x: imageRect.minX + point.x * scale, y: imageRect.minY + point.y * scale)
        let fieldWidth = min(max(180, 220 * scale), max(120, bounds.maxX - origin.x - 8))
        let fieldHeight = max(28, min(64, 32 * scale))
        let fieldOrigin = CGPoint(x: min(max(bounds.minX + 8, origin.x), max(bounds.minX + 8, bounds.maxX - fieldWidth - 8)), y: min(max(bounds.minY + 8, origin.y), max(bounds.minY + 8, bounds.maxY - fieldHeight - 8)))
        let field = NSTextField(frame: NSRect(origin: fieldOrigin, size: NSSize(width: fieldWidth, height: fieldHeight)))
        field.stringValue = markIndex.map { marks[$0].text } ?? mark.text
        field.isBezeled = true
        field.drawsBackground = true
        field.backgroundColor = .controlBackgroundColor
        let imageScale = pixelSize.width / max(1, image.size.width)
        let editingFontSize = max(12, min(36, CGFloat(mark.style.resolvedFontSize) * imageScale * scale))
        field.font = NSFont(name: mark.style.fontName, size: editingFontSize) ?? NSFont.systemFont(ofSize: editingFontSize)
        switch mark.tool {
        case .note: field.placeholderString = "输入备注，按回车完成"; field.setAccessibilityLabel("备注内容")
        case .step: field.placeholderString = "输入步骤说明，按回车完成"; field.setAccessibilityLabel("步骤说明")
        default: field.placeholderString = "输入文字，按回车完成"; field.setAccessibilityLabel("标注文字")
        }
        field.delegate = self
        addSubview(field)
        inlineEditor = field; editingIndex = markIndex
        focusInlineEditor(selectAll: true)
    }
    private func focusInlineEditor(selectAll: Bool = false) {
        guard let field = inlineEditor, let window else { return }
        activateEditorWindowForEditing()
        guard window.isKeyWindow else { return }
        if window.firstResponder !== field.currentEditor(), !window.makeFirstResponder(field) { return }
        if selectAll { field.selectText(nil) }
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { finishTextEditing(save: true); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { finishTextEditing(save: false); return true }
        return false
    }
    public func control(_ control: NSControl, textView: NSTextView, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        guard draftMark?.tool == .watermark else { return true }
        let currentLength = (textView.string as NSString).length
        return currentLength - range.length + (string as NSString).length <= 16
    }
    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let endedField = notification.object as? NSTextField, let inlineEditor, endedField === inlineEditor else { return }
        if draftMark != nil, endedField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return }
        finishTextEditing(save: true)
    }
    private func finishTextEditing(save: Bool) {
        guard let field = inlineEditor else { return }
        let value = field.stringValue
        field.delegate = nil; field.removeFromSuperview(); inlineEditor = nil
        if save {
            if let editingIndex, marks.indices.contains(editingIndex) {
                if marks[editingIndex].text != value {
                    editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
                    marks[editingIndex].text = value
                    invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
                }
            } else if var draftMark, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftMark.text = value; append(draftMark)
                if draftMark.tool == .step { number = max(number, (draftMark.stepNumber ?? number) + 1) }
            }
        }
        editingIndex = nil; draftMark = nil
        window?.makeFirstResponder(self)
    }
    private func markBounds(_ mark: EditorMark) -> CGRect {
        guard let first = mark.points.first else { return .zero }
        if mark.tool == .sticker {
            let last = mark.points.last ?? first
            let width = max(48, abs(last.x - first.x)), height = max(48, abs(last.y - first.y))
            return CGRect(x: first.x, y: first.y, width: width, height: height)
        }
        if [.text, .note, .number, .step, .sticker, .watermark].contains(mark.tool) {
            let imageScale = pixelSize.width / max(1, image.size.width)
            let font = NSFont(name: mark.style.fontName, size: CGFloat(mark.style.resolvedFontSize) * imageScale) ?? NSFont.systemFont(ofSize: 17 * imageScale)
            let textSize = (mark.text as NSString).size(withAttributes: [.font: font])
            if mark.tool == .step {
                let anchor = mark.points.first ?? .zero, label = mark.points.last ?? anchor
                let badge = max(30, CGFloat(mark.style.resolvedFontSize) * imageScale * 1.7)
                let bubble = CGRect(x: label.x, y: label.y, width: textSize.width + 24, height: textSize.height + 18)
                return CGRect(x: min(anchor.x, bubble.minX), y: min(anchor.y, bubble.minY), width: max(anchor.x + badge, bubble.maxX) - min(anchor.x, bubble.minX), height: max(anchor.y + badge, bubble.maxY) - min(anchor.y, bubble.minY))
            }
            let width = mark.tool == .number ? max(30, textSize.width + 14) : textSize.width + (mark.tool == .note ? 24 : 8)
            let height = mark.tool == .number ? max(30, textSize.width + 14) : textSize.height + (mark.tool == .note ? 18 : 8)
            return CGRect(x: first.x, y: first.y, width: width, height: height)
        }
        let xs = mark.points.map(\.x), ys = mark.points.map(\.y)
        return CGRect(x: xs.min() ?? first.x, y: ys.min() ?? first.y, width: (xs.max() ?? first.x) - (xs.min() ?? first.x), height: (ys.max() ?? first.y) - (ys.min() ?? first.y))
    }
    private func hitTestMark(at point: CGPoint) -> Int? {
        marks.indices.reversed().first { index in
            let bounds = markBounds(marks[index]).insetBy(dx: -max(8, marks[index].width), dy: -max(8, marks[index].width))
            return bounds.contains(point)
        }
    }
    public var selectedMarkIndex: Int? { selectedIndex }
    public func updateSelectedStyle(_ style: AnnotationStyle) {
        guard let selectedIndex, marks.indices.contains(selectedIndex), marks[selectedIndex].style != style else { return }
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        if marks[selectedIndex].tool == .step, marks[selectedIndex].style.stepDirection != style.stepDirection, let anchor = marks[selectedIndex].points.first {
            let previous = marks[selectedIndex].points.last ?? anchor
            let distance = max(54, hypot(previous.x-anchor.x,previous.y-anchor.y))
            marks[selectedIndex].points = [anchor,stepLabelPoint(from:anchor,direction:style.stepDirection,distance:distance)]
        }
        marks[selectedIndex].style = style; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    public func updateSelectedColor(_ color: NSColor) {
        guard let selectedIndex, marks.indices.contains(selectedIndex) else { return }
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        marks[selectedIndex].color = color; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    public func updateSelectedWidth(_ width: CGFloat) {
        guard let selectedIndex, marks.indices.contains(selectedIndex), marks[selectedIndex].width != width else { return }
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        marks[selectedIndex].width = width; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    public func deleteSelectedMark() {
        guard let selectedIndex, marks.indices.contains(selectedIndex) else { return }
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        marks.remove(at: selectedIndex); self.selectedIndex = nil; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
        onSelectionChanged?(nil)
    }
    public func copySelectedMark() {
        guard let selectedIndex, marks.indices.contains(selectedIndex) else { return }
        copiedMark = marks[selectedIndex]
    }
    public func pasteCopiedMark() {
        guard var copiedMark else { return }
        copiedMark.points = copiedMark.points.map { CGPoint(x: $0.x + 16, y: $0.y + 16) }
        append(copiedMark); selectedIndex = marks.indices.last; needsDisplay = true
    }
    public func duplicateSelectedMark() {
        copySelectedMark(); pasteCopiedMark()
    }
    public func addAnnotation(_ mark: EditorMark) { append(mark) }
    public func undoLastEdit() { editingUndoManager.undo(); invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks) }
    public func redoLastEdit() { editingUndoManager.redo(); invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks) }
    private func append(_ mark: EditorMark) {
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        marks.append(mark); invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    private func registerStateUndo(image previousImage: NSImage? = nil, marks previousMarks: [EditorMark]? = nil) {
        let oldImage = previousImage ?? image
        let oldMarks = previousMarks ?? marks
        editingUndoManager.registerUndo(withTarget: self) { target in
            let currentImage = target.image, currentMarks = target.marks
            target.registerStateUndo(image: currentImage, marks: currentMarks)
            target.image = oldImage; target.marks = oldMarks; target.invalidateComposite(); target.needsDisplay = true
        }
    }
    func applyCrop() {
        guard let points = cropSelection, points.width > 1, points.height > 1 else { return }
        do {
            try cropImage(to: points)
        } catch {
            let alert = NSAlert(error: error); alert.runModal()
        }
    }
    public func cropImage(to rect: CGRect) throws {
        let cropped = try ImageProcessing.crop(image: image, rect: rect)
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        image = cropped
        marks = marks.map { mark in var shifted = mark;shifted.points = mark.points.map { CGPoint(x:$0.x-rect.minX,y:$0.y-rect.minY) };return shifted }
        cropSelection = nil; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    private func currentBounds() -> CGRect { guard let a = currentPoints.first, let b = currentPoints.last else { return .zero }; return CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y)) }
    private func hexAt(_ point: CGPoint) -> String {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return "—" }
        let x = min(cg.width-1,max(0,Int(point.x))),y = min(cg.height-1,max(0,Int(point.y)))
        guard let color = NSBitmapImageRep(cgImage:cg).colorAt(x:x,y:y)?.usingColorSpace(.sRGB) else { return "—" }
        return String(format: "#%02X%02X%02X",Int((color.redComponent*255).rounded()),Int((color.greenComponent*255).rounded()),Int((color.blueComponent*255).rounded()))
    }
    public func renderedImage() -> NSImage { compositedImage(includePreview: false) }
    public var imageForDocument: NSImage { image }
    public var annotationsForDocument: [EditorMark] { marks }
    public func renderedImage(cornerRadius: CGFloat, shadow: Bool, scaleToOneX: Bool, shadowStrength: CGFloat = 0.36) -> NSImage {
        finishTextEditing(save:true)
        return ImageEditorRenderer.render(image: image, marks: marks, cornerRadius: cornerRadius, shadow: shadow, scaleToOneX: scaleToOneX, shadowOpacity: shadowStrength)
    }
    public func replaceImage(_ replacement: NSImage) {
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        image = replacement; marks.removeAll(); cropSelection = nil; invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
    public func extendCanvas(padding: Int, color: NSColor) {
        guard padding > 0, let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let newWidth = source.width + padding * 2, newHeight = source.height + padding * 2
        guard let context = CGContext(data: nil, width: newWidth, height: newHeight, bitsPerComponent: 8, bytesPerRow: newWidth * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.setFillColor(color.cgColor); context.fill(CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        context.draw(source, in: CGRect(x: padding, y: padding, width: source.width, height: source.height))
        guard let cg = context.makeImage() else { return }
        editingUndoManager.beginUndoGrouping(); registerStateUndo(); editingUndoManager.endUndoGrouping()
        image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        marks = marks.map { mark in var shifted = mark; shifted.points = mark.points.map { CGPoint(x: $0.x + CGFloat(padding), y: $0.y + CGFloat(padding)) }; return shifted }
        invalidateComposite(); needsDisplay = true; onDocumentChanged?(image, marks)
    }
}

public enum ImageEditorRenderer {
    public static func render(image: NSImage, marks: [EditorMark]) -> NSImage {
        render(image: image, marks: marks, cornerRadius: 0, shadow: false, scaleToOneX: false)
    }

    public static func render(image: NSImage, marks: [EditorMark], cornerRadius: CGFloat, shadow: Bool, scaleToOneX: Bool, shadowOpacity: CGFloat = 0.36) -> NSImage {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = source.width, height = source.height
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
        let context = graphics.cgContext
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        let pixelsPerPoint = CGFloat(width) / max(1, image.size.width)
        for mark in marks {
            var renderedMark = mark
            if mark.style.colorPreset == .theme { renderedMark.color = AnnotationTheme.color }
            renderedMark.width *= pixelsPerPoint
            renderedMark.style.fontSize = mark.style.resolvedFontSize * pixelsPerPoint
            drawMark(renderedMark, context: context, width: width, height: height, pixelsPerPoint: pixelsPerPoint)
        }
        context.flush(); NSGraphicsContext.restoreGraphicsState()
        let composed = NSImage(size: image.size); composed.addRepresentation(bitmap)
        let styled = applyFrame(to: composed, cornerRadius: cornerRadius * pixelsPerPoint, shadow: shadow, shadowOpacity: shadowOpacity, pixelsPerPoint: pixelsPerPoint)
        guard scaleToOneX else { return styled }
        let ratio = min(image.size.width / CGFloat(width), image.size.height / CGFloat(height))
        return resize(styled, factor: ratio)
    }

    private static func applyFrame(to image: NSImage, cornerRadius: CGFloat, shadow: Bool, shadowOpacity: CGFloat, pixelsPerPoint: CGFloat) -> NSImage {
        guard cornerRadius > 0 || shadow,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let pad = shadow ? 24 : 0
        let width = source.width + pad * 2, height = source.height + pad * 2
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let imageRect = CGRect(x: pad, y: pad, width: source.width, height: source.height)
        let radius = min(cornerRadius, CGFloat(min(source.width, source.height)) / 2)
        let path = CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if shadow {
            context.saveGState(); context.setShadow(offset: CGSize(width: 0, height: -5), blur: 12, color: NSColor.black.withAlphaComponent(shadowOpacity).cgColor)
            context.addPath(path); context.setFillColor(NSColor.black.cgColor); context.fillPath(); context.restoreGState()
        }
        context.saveGState(); context.addPath(path); context.clip()
        context.draw(source, in: imageRect); context.restoreGState()
        let result = NSImage(size: NSSize(width: CGFloat(width) / pixelsPerPoint, height: CGFloat(height) / pixelsPerPoint)); result.addRepresentation(bitmap)
        return result
    }

    private static func resize(_ image: NSImage, factor: CGFloat) -> NSImage {
        guard factor > 0, factor < 0.999,
              let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let width = max(1, Int((CGFloat(source.width) * factor).rounded()))
        let height = max(1, Int((CGFloat(source.height) * factor).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let resized = context.makeImage() else { return image }
        return NSImage(cgImage: resized, size: NSSize(width: width, height: height))
    }

    fileprivate static func drawMark(_ mark: EditorMark, context: CGContext, width: Int, height: Int, pixelsPerPoint: CGFloat = 1) {
        guard let first = mark.points.first else { return }
        let end = mark.points.last ?? first
        let rect = CGRect(x: min(first.x, end.x), y: min(first.y, end.y), width: abs(end.x - first.x), height: abs(end.y - first.y))
        switch mark.tool {
        case .mosaic, .blur:
            let brushRadius = mark.tool == .mosaic ? CGFloat(mark.style.mosaicMode.radius) * pixelsPerPoint : 0
            let effectBounds = brushRadius > 0 ? rect.insetBy(dx: -brushRadius, dy: -brushRadius) : rect
            let box = effectBounds.integral.intersection(CGRect(x: 0, y: 0, width: width, height: height))
            guard box.width > 0, box.height > 0, let source = context.makeImage() else { return }
            let ci = CIImage(cgImage: source)
            let blurStyle = mark.tool == .blur || [.lightBlur, .gaussianBlur, .strongBlur].contains(mark.style.mosaicStyle)
            let filter = blurStyle ? CIFilter(name: "CIGaussianBlur") : CIFilter(name: "CIPixellate")
            filter?.setValue(blurStyle ? ci.clampedToExtent() : ci, forKey: kCIInputImageKey)
            let blurRadius: CGFloat = switch mark.style.mosaicStyle { case .lightBlur: 5; case .strongBlur: 24; default: max(8, mark.width * 2) }
            let pixelScale: CGFloat = switch mark.style.mosaicStyle { case .finePixelated: 6; case .coarsePixelated: 24; default: 12 }
            filter?.setValue(blurStyle ? blurRadius : pixelScale, forKey: blurStyle ? kCIInputRadiusKey : kCIInputScaleKey)
            guard let output = filter?.outputImage?.cropped(to: ci.extent),
                  let effected = CIContext().createCGImage(output, from: ci.extent) else { return }
            let effectedBitmap = NSBitmapImageRep(cgImage: effected)
            guard let destination = context.data?.assumingMemoryBound(to: UInt8.self) else { return }
            for y in Int(box.minY)..<Int(box.maxY) {
                for x in Int(box.minX)..<Int(box.maxX) {
                    if brushRadius > 0 && !mark.points.contains(where: { hypot(CGFloat(x) - $0.x, CGFloat(y) - $0.y) <= brushRadius }) { continue }
                    guard let color = effectedBitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    let offset = y * context.bytesPerRow + x * 4
                    let alpha = color.alphaComponent
                    destination[offset] = UInt8((color.redComponent * alpha * 255).rounded())
                    destination[offset + 1] = UInt8((color.greenComponent * alpha * 255).rounded())
                    destination[offset + 2] = UInt8((color.blueComponent * alpha * 255).rounded())
                    destination[offset + 3] = UInt8((alpha * 255).rounded())
                }
            }
            context.flush()
        case .highlight:
            let region = rect.standardized.intersection(CGRect(x:0,y:0,width:width,height:height))
            context.setFillColor(mark.color.withAlphaComponent(mark.style.highlightOpacity).cgColor)
            context.fill(region)
        case .text, .number, .step, .note, .sticker, .watermark:
            let fontSize = mark.tool == .number ? max(18, mark.width * 5) : (mark.tool == .sticker ? max(30, mark.width * 8) : CGFloat(mark.style.fontSize))
            let font = NSFont(name: mark.style.fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
            var fontTraits: NSFontTraitMask = []
            if mark.style.bold { fontTraits.insert(.boldFontMask) }; if mark.style.italic { fontTraits.insert(.italicFontMask) }
            let styledFont = NSFontManager.shared.convert(font, toHaveTrait: fontTraits)
            var attributes: [NSAttributedString.Key: Any] = [.font: styledFont, .foregroundColor: mark.color]
            if mark.style.underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if mark.style.strikethrough { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            let string = mark.text
            let measured = (string as NSString).size(withAttributes: attributes)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            if mark.tool == .number {
                let circle = CGRect(x: first.x, y: first.y, width: max(30, measured.width + 14), height: max(30, measured.width + 14))
                let path = NSBezierPath(ovalIn: circle); mark.color.setFill(); path.fill()
                (string as NSString).draw(at: CGPoint(x: circle.midX - measured.width / 2, y: circle.midY - measured.height / 2), withAttributes: [.font: font, .foregroundColor: NSColor.white])
            } else if mark.tool == .step {
                let badgeSize = max(30, fontSize * 1.7)
                let badge = CGRect(x: first.x, y: first.y, width: badgeSize, height: badgeSize)
                let labelOrigin = mark.points.count > 1 ? mark.points[1] : CGPoint(x: badge.maxX + 10, y: first.y)
                let bubble = CGRect(x: labelOrigin.x, y: labelOrigin.y, width: measured.width + 24, height: measured.height + 18)
                let background = mark.style.textBackground?.nsColor ?? NSColor(calibratedWhite: 1, alpha: 0.96)
                let outline = mark.style.textOutline?.nsColor ?? mark.color
                let badgeCenter = CGPoint(x: badge.midX, y: badge.midY)
                let bubbleEdge = nearestEdgePoint(on: bubble, from: badgeCenter)
                let direction = CGPoint(x: bubbleEdge.x - badgeCenter.x, y: bubbleEdge.y - badgeCenter.y)
                let directionLength = max(0.001, hypot(direction.x, direction.y))
                let unit = CGPoint(x: direction.x / directionLength, y: direction.y / directionLength)
                let badgeEdge = CGPoint(x: badgeCenter.x + unit.x * min(badge.width, badge.height) / 2, y: badgeCenter.y + unit.y * min(badge.width, badge.height) / 2)
                context.saveGState()
                if mark.style.step == .integrated {
                    let bridgeLength = hypot(bubbleEdge.x - badgeEdge.x, bubbleEdge.y - badgeEdge.y)
                    let bridgeWidth = min(18, max(10, min(badge.width, bubble.height) * 0.42))
                    var transform = CGAffineTransform(translationX: (badgeEdge.x + bubbleEdge.x) / 2, y: (badgeEdge.y + bubbleEdge.y) / 2).rotated(by: atan2(bubbleEdge.y - badgeEdge.y, bubbleEdge.x - badgeEdge.x))
                    let bridgePath = CGPath(roundedRect: CGRect(x: -bridgeLength / 2, y: -bridgeWidth / 2, width: max(4, bridgeLength), height: bridgeWidth), cornerWidth: bridgeWidth / 2, cornerHeight: bridgeWidth / 2, transform: &transform)
                    context.addPath(bridgePath); context.setFillColor(background.cgColor); context.setStrokeColor(outline.cgColor); context.setLineWidth(max(1, mark.width)); context.drawPath(using: .fillStroke)
                } else {
                    context.setStrokeColor(mark.color.cgColor)
                    context.setLineWidth(max(1.5, mark.width * 0.65))
                    context.move(to: badgeEdge); context.addLine(to: bubbleEdge); context.strokePath()
                }
                let bubblePath = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)
                background.setFill(); bubblePath.fill(); outline.setStroke(); bubblePath.lineWidth = max(1, mark.width); bubblePath.stroke()
                let badgePath = NSBezierPath(ovalIn: badge); mark.color.setFill(); badgePath.fill()
                let numberText = "\(mark.stepNumber ?? Int(mark.text) ?? 1)"
                let numberFont = NSFont.boldSystemFont(ofSize: max(12, badgeSize * 0.48))
                let numberSize = (numberText as NSString).size(withAttributes: [.font: numberFont])
                (numberText as NSString).draw(at: CGPoint(x: badge.midX - numberSize.width / 2, y: badge.midY - numberSize.height / 2), withAttributes: [.font: numberFont, .foregroundColor: NSColor.white])
                (string as NSString).draw(in: CGRect(x: bubble.minX + 12, y: bubble.minY + 9, width: max(0, bubble.width - 24), height: max(0, bubble.height - 18)), withAttributes: attributes)
                context.restoreGState()
            } else if mark.tool == .note {
                let bubble = CGRect(x: first.x, y: first.y, width: measured.width + 24, height: measured.height + 18)
                let path = NSBezierPath(roundedRect: bubble, xRadius: 8, yRadius: 8)
                (mark.style.textBackground?.nsColor ?? NSColor(calibratedWhite: 1, alpha: 0.94)).setFill(); path.fill()
                (mark.style.textOutline?.nsColor ?? mark.color).setStroke(); path.lineWidth = max(1, mark.width); path.stroke()
                (string as NSString).draw(at: CGPoint(x: first.x + 12, y: first.y + 9), withAttributes: attributes)
            } else if mark.tool == .sticker {
                let stickerSize = 48 * pixelsPerPoint
                let stickerRect = rect.width < 4 || rect.height < 4 ? CGRect(x: first.x, y: first.y, width: stickerSize, height: stickerSize) : rect
                let c = context
                c.saveGState()
                c.translateBy(x: stickerRect.midX, y: stickerRect.midY); c.rotate(by: mark.style.stickerRotation * .pi / 180)
                if let data = mark.style.sticker?.pngData, let sticker = NSImage(data: data) {
                    sticker.draw(in: CGRect(x: -stickerRect.width / 2, y: -stickerRect.height / 2, width: stickerRect.width, height: stickerRect.height), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                } else {
                    let localRect = CGRect(x: -stickerRect.width / 2, y: -stickerRect.height / 2, width: stickerRect.width, height: stickerRect.height)
                    (string as NSString).draw(in: localRect, withAttributes: [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: mark.color])
                }
                c.restoreGState()
            } else if mark.tool == .watermark {
                if mark.style.watermarkVisible {
                    let watermark = mark.color.withAlphaComponent(min(mark.color.alphaComponent, mark.style.watermarkOpacity))
                    var attrs = attributes
                    attrs[.foregroundColor] = watermark
                    let stepX = max(100, measured.width * 3 / max(0.25, mark.style.watermarkDensity))
                    let stepY = max(80, fontSize * 4 / max(0.25, mark.style.watermarkDensity))
                    for y in stride(from: CGFloat(0), through: CGFloat(height), by: stepY) {
                        for x in stride(from: CGFloat(0), through: CGFloat(width), by: stepX) {
                            let transform = NSAffineTransform()
                            transform.translateX(by: x, yBy: y)
                            transform.rotate(byDegrees: mark.style.watermarkAngle)
                            transform.concat()
                            (string as NSString).draw(at: .zero, withAttributes: attrs)
                            transform.invert(); transform.concat()
                        }
                    }
                }
            } else {
                if let background = mark.style.textBackground {
                    let box = CGRect(x: first.x - 2, y: first.y - 2, width: measured.width + 4, height: measured.height + 4)
                    background.nsColor.setFill(); NSBezierPath(rect: box).fill()
                    mark.style.textOutline?.nsColor.setStroke(); NSBezierPath(rect: box).stroke()
                }
                (string as NSString).draw(at: first, withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState()
        case .shape:
            let path = shapePath(mark.style.shape, in: rect)
            context.saveGState()
            context.setStrokeColor(mark.style.textOutline?.nsColor.cgColor ?? mark.color.cgColor)
            context.setLineWidth(mark.width)
            if mark.style.fill == .dashedOutline || mark.style.fill == .dashedTranslucent { context.setLineDash(phase: 0, lengths: [max(4, mark.width * 2), max(3, mark.width * 1.5)]) }
            if mark.style.fill == .translucent || mark.style.fill == .dashedTranslucent {
                context.addPath(path); context.setFillColor((mark.style.fillColor?.nsColor ?? mark.color).withAlphaComponent(0.3).cgColor); context.drawPath(using: .fillStroke)
            } else if mark.style.fill == .solid {
                context.addPath(path); context.setFillColor((mark.style.fillColor?.nsColor ?? mark.color).cgColor); context.drawPath(using: .fillStroke)
            } else if mark.style.fill == .hatched {
                context.addPath(path); context.saveGState(); context.clip()
                context.setStrokeColor((mark.style.fillColor?.nsColor ?? mark.color).withAlphaComponent(0.55).cgColor); context.setLineWidth(max(1, mark.width / 2))
                let bounds = path.boundingBoxOfPath
                var x = bounds.minX - bounds.height
                while x < bounds.maxX { context.move(to: CGPoint(x: x, y: bounds.maxY)); context.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY)); x += max(7, mark.width * 3) }
                context.strokePath(); context.restoreGState()
                if mark.style.fill == .hatched { context.addPath(path); context.strokePath() }
            } else {
                context.addPath(path); context.strokePath()
            }
            context.restoreGState()
            if !mark.text.isEmpty {
                let font = NSFont(name: mark.style.fontName, size: CGFloat(mark.style.fontSize)) ?? NSFont.systemFont(ofSize: CGFloat(mark.style.fontSize))
                var fontTraits: NSFontTraitMask = []
                if mark.style.bold { fontTraits.insert(.boldFontMask) }; if mark.style.italic { fontTraits.insert(.italicFontMask) }
                let styledFont = NSFontManager.shared.convert(font, toHaveTrait: fontTraits)
                var attrs: [NSAttributedString.Key: Any] = [.font: styledFont, .foregroundColor: mark.color]
                if mark.style.underline { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
                if mark.style.strikethrough { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
                let textSize = (mark.text as NSString).size(withAttributes: attrs)
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
                (mark.text as NSString).draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attrs)
                NSGraphicsContext.restoreGraphicsState()
            }
        case .magnifier:
            let target = rect.standardized.integral
            let sourceWidth = rect.width / CGFloat(max(1.1, mark.style.magnifierScale))
            let sourceHeight = rect.height / CGFloat(max(1.1, mark.style.magnifierScale))
            let sourceRect = CGRect(x: rect.midX - sourceWidth / 2, y: rect.midY - sourceHeight / 2, width: max(2, sourceWidth), height: max(2, sourceHeight)).integral
            guard target.width > 2, target.height > 2, let snapshot = context.makeImage() else { return }
            let cropRect = sourceRect
            guard let crop = snapshot.cropping(to: cropRect) else { return }
            context.saveGState(); context.addEllipse(in: target); context.clip()
            context.draw(crop, in: target); context.restoreGState()
            context.saveGState(); context.setStrokeColor(mark.color.cgColor); context.setLineWidth(max(2, mark.width)); context.strokeEllipse(in: target); context.restoreGState()
        default:
            let path = CGMutablePath()
            if mark.tool == .pen {
                path.move(to: first); for point in mark.points.dropFirst() { path.addLine(to: point) }
            } else if mark.tool == .rectangle { path.addRect(rect) }
            else if mark.tool == .ellipse { path.addEllipse(in: rect) }
            else { path.move(to: first); path.addLine(to: end) }
            context.saveGState()
            let highlighter = mark.tool == .pen && mark.style.brush == .highlighter
            let mainLineWidth = highlighter ? max(mark.width * 3, 14) : mark.width
            context.setLineCap(.round); context.setLineJoin(.round)
            context.setAlpha(highlighter ? 0.35 : 1)
            if mark.tool == .arrow && mark.style.arrow.dashed { context.setLineDash(phase: 0, lengths: [max(5, mark.width * 2), max(4, mark.width * 1.5)]) }
            if [.arrow, .pen].contains(mark.tool), let outlineColor = mark.style.textOutline?.nsColor {
                context.setStrokeColor(outlineColor.cgColor)
                context.setLineWidth(mainLineWidth + max(2, mark.width * 2))
                context.addPath(path); context.strokePath()
            }
            context.setStrokeColor(mark.color.cgColor)
            context.setLineWidth(mainLineWidth)
            context.addPath(path); context.strokePath()
            if mark.tool == .arrow && mark.style.arrow.hasHead {
                context.setLineDash(phase: 0, lengths: [])
                if let outlineColor = mark.style.textOutline?.nsColor {
                    drawArrowHead(at: end, toward: first, mark: mark, context: context, strokeColor: outlineColor, expanded: true)
                    if mark.style.arrow.hasTail { drawArrowHead(at: first, toward: end, mark: mark, context: context, strokeColor: outlineColor, expanded: true) }
                }
                drawArrowHead(at: end, toward: first, mark: mark, context: context)
                if mark.style.arrow.hasTail { drawArrowHead(at: first, toward: end, mark: mark, context: context) }
            }
            context.restoreGState()
        }
    }

    private static func shapePath(_ shape: AnnotationShape, in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .rectangle: path.addRect(rect)
        case .roundedRectangle: path.addRoundedRect(in: rect, cornerWidth: min(14, rect.height / 4), cornerHeight: min(14, rect.height / 4))
        case .circle: path.addEllipse(in: rect)
        case .triangle, .star, .pentagon, .hexagon:
            let count = shape == .triangle ? 3 : (shape == .star ? 10 : (shape == .pentagon ? 5 : 6))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            for index in 0..<count {
                let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
                let factor: CGFloat = shape == .star && index.isMultiple(of: 2) ? 1 : (shape == .star ? 0.42 : 1)
                let point = CGPoint(x: center.x + cos(angle) * rect.width / 2 * factor, y: center.y + sin(angle) * rect.height / 2 * factor)
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        case .chatBubble:
            let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height * 0.78)
            path.addRoundedRect(in: body, cornerWidth: min(12, body.height / 4), cornerHeight: min(12, body.height / 4))
            path.move(to: CGPoint(x: rect.minX + rect.width * 0.28, y: body.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.47, y: body.maxY))
            path.closeSubpath()
        }
        return path
    }

    private static func nearestEdgePoint(on rect: CGRect, from point: CGPoint) -> CGPoint {
        let clamped = CGPoint(x: min(rect.maxX, max(rect.minX, point.x)), y: min(rect.maxY, max(rect.minY, point.y)))
        if clamped != point { return clamped }
        let distances: [(CGFloat, CGPoint)] = [
            (abs(point.x - rect.minX), CGPoint(x: rect.minX, y: point.y)),
            (abs(rect.maxX - point.x), CGPoint(x: rect.maxX, y: point.y)),
            (abs(point.y - rect.minY), CGPoint(x: point.x, y: rect.minY)),
            (abs(rect.maxY - point.y), CGPoint(x: point.x, y: rect.maxY))
        ]
        return distances.min(by: { $0.0 < $1.0 })?.1 ?? CGPoint(x: rect.minX, y: rect.midY)
    }

    private static func drawArrowHead(at point: CGPoint, toward other: CGPoint, mark: EditorMark, context: CGContext, strokeColor: NSColor? = nil, expanded: Bool = false) {
        let angle = atan2(point.y - other.y, point.x - other.x)
        let expansion = expanded ? max(2, mark.width * 1.5) : 0
        let size = max(mark.width * 4, 12) + expansion
        let left = CGPoint(x: point.x - size * cos(angle - .pi / 6), y: point.y - size * sin(angle - .pi / 6))
        let right = CGPoint(x: point.x - size * cos(angle + .pi / 6), y: point.y - size * sin(angle + .pi / 6))
        let head = CGMutablePath(); head.move(to: point); head.addLine(to: left); head.move(to: point); head.addLine(to: right)
        context.setStrokeColor((strokeColor ?? mark.color).cgColor)
        context.setLineWidth(mark.width + (expanded ? max(2, mark.width * 2) : 0))
        if mark.style.arrow == .cone {
            head.addLine(to: left); head.closeSubpath(); context.addPath(head); context.setFillColor((strokeColor ?? mark.color).cgColor); context.fillPath()
        } else { context.addPath(head); context.strokePath() }
    }
}
