import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

@MainActor enum ScreenshotExport {
    static func name(template:String,title:String = "ScreenshotKing",format:String,date:Date = Date())->String {
        var result = template.replacingOccurrences(of:"%title%",with:title)
        let pattern = try! NSRegularExpression(pattern:"\\$([^$]+)\\$")
        for match in pattern.matches(in:result,range:NSRange(result.startIndex...,in:result)).reversed() {
            let raw = result as NSString;let formatter = DateFormatter();formatter.dateFormat = raw.substring(with:match.range(at:1))
            result = raw.replacingCharacters(in:match.range,with:formatter.string(from:date))
        }
        for character in ["/","\\",":","\n","\r"] { result = result.replacingOccurrences(of:character,with:"_") }
        result = result.trimmingCharacters(in:.whitespacesAndNewlines)
        if ["png","jpg","jpeg","heic"].contains((result as NSString).pathExtension.lowercased()) { result = (result as NSString).deletingPathExtension }
        if result.isEmpty || result == "." || result == ".." { result = "ScreenshotKing" }
        return String(result.prefix(180)) + "." + format
    }
    @discardableResult static func save(_ image:NSImage,defaults:UserDefaults = .standard,date:Date = Date(),silently:Bool = false) throws -> URL? {
        defaults.register(defaults:["exportAsk":true,"exportFormat":"png","exportTemplate":"ScreenshotKing_$yyyy-MM-dd_HH-mm-ss$","exportReveal":false,"exportCopyPath":false])
        let format = defaults.string(forKey:"exportFormat")!
        guard ["png","jpg","heic"].contains(format) else { throw error("不支持的输出格式：\(format)") }
        let fileName = name(template:defaults.string(forKey:"exportTemplate")!,format:format,date:date)
        let configuredFolder = defaults.string(forKey:"exportDirectory").flatMap { $0.isEmpty ? nil : URL(fileURLWithPath:$0,isDirectory:true) }
        let folder = silently ? (configuredFolder ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/ScreenshotKing",isDirectory:true)) : configuredFolder
        let url:URL
        if !silently && (defaults.bool(forKey:"exportAsk") || folder == nil) {
            let panel = NSSavePanel();panel.allowedContentTypes = [.png,.jpeg,.heic]
            panel.nameFieldStringValue = fileName;panel.directoryURL = folder
            guard panel.runModal() == .OK,let selected = panel.url else { return nil };url = selected
        } else {
            let folder = folder!
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            var candidate = folder.appendingPathComponent(fileName)
            let base = candidate.deletingPathExtension();var suffix = 2
            while FileManager.default.fileExists(atPath:candidate.path) { candidate = base.appendingPathExtension("\(suffix).\(format)");suffix += 1 }
            url = candidate
        }
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw error("无法读取输出图像") }
        let ext = url.pathExtension.lowercased()
        let uti:CFString
        switch ext { case "png":uti = UTType.png.identifier as CFString;case "heic":uti = UTType.heic.identifier as CFString;case "jpg","jpeg":uti = UTType.jpeg.identifier as CFString;default:throw error("不支持的文件扩展名：\(ext)") }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,uti,1,nil) else { throw error("无法创建图片编码器") }
        CGImageDestinationAddImage(destination,cg,[kCGImageDestinationLossyCompressionQuality:0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw error("图片编码失败") }
        try (data as Data).write(to:url,options:.atomic)
        if !silently && defaults.bool(forKey:"exportReveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        if !silently && defaults.bool(forKey:"exportCopyPath") { NSPasteboard.general.clearContents();NSPasteboard.general.setString(url.path,forType:.string) }
        return url
    }
    private static func error(_ text:String)->NSError { NSError(domain:"ScreenshotKing.Export",code:1,userInfo:[NSLocalizedDescriptionKey:text]) }
}

struct ExportSettingsView:View {
    @AppStorage("exportAsk") private var ask = true
    @AppStorage("exportDirectory") private var directory = ""
    @AppStorage("exportFormat") private var format = "png"
    @AppStorage("exportTemplate") private var template = "ScreenshotKing_$yyyy-MM-dd_HH-mm-ss$"
    @AppStorage("exportReveal") private var reveal = false
    @AppStorage("exportCopyPath") private var copyPath = false
    var body:some View {
        Form {
            TextField("文件命名",text:$template).textFieldStyle(.roundedBorder)
            Text("$yyyy-MM-dd_HH-mm-ss$ 表示时间；%title% 表示图片标题。自动保存不会覆盖已有文件。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Picker("默认格式",selection:$format) { Text("PNG（无损）").tag("png");Text("HEIC").tag("heic");Text("JPEG").tag("jpg") }
            HStack { Text(directory.isEmpty ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/ScreenshotKing",isDirectory:true).path : directory).lineLimit(2).textSelection(.enabled);Spacer();Button("选择文件夹…") { chooseFolder() } }
            Text("未选择文件夹时，静默截图保存到上方路径。静默保存会跳过保存位置询问、Finder 显示和复制文件路径设置。")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
            Toggle("每次询问保存位置",isOn:$ask).disabled(directory.isEmpty)
            Toggle("保存后在 Finder 中选中",isOn:$reveal)
            Toggle("保存后复制文件路径",isOn:$copyPath)
        }.padding(24)
    }
    private func chooseFolder() {
        let panel = NSOpenPanel();panel.canChooseDirectories = true;panel.canChooseFiles = false;panel.canCreateDirectories = true
        if panel.runModal() == .OK,let url = panel.url { directory = url.path }
    }
}
