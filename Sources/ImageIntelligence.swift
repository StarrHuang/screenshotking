import AppKit
import SwiftUI
import Vision
import Translation

struct RecognizedBlock: Sendable {
    let text: String
    let bounds: CGRect // Vision normalized lower-left coordinates
}

enum ImageRecognition {
    static func read(_ image: CGImage) throws -> (blocks: [RecognizedBlock], codes: [String]) {
        let text = VNRecognizeTextRequest(); text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true; text.automaticallyDetectsLanguage = true
        let barcode = VNDetectBarcodesRequest()
        try VNImageRequestHandler(cgImage:image).perform([text,barcode])
        let blocks = (text.results ?? []).compactMap { observation -> RecognizedBlock? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return RecognizedBlock(text:candidate.string,bounds:observation.boundingBox)
        }
        return (blocks, (barcode.results ?? []).compactMap(\.payloadStringValue))
    }
    @MainActor static func renderTranslations(image: NSImage, blocks: [RecognizedBlock], strings: [String]) throws -> NSImage {
        guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let context = CGContext(data:nil,width:cg.width,height:cg.height,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw NSError(domain:"ScreenshotKing",code:3,userInfo:[NSLocalizedDescriptionKey:"无法生成翻译图片"])
        }
        context.draw(cg,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        for (block,translated) in zip(blocks,strings) {
            let bounds = CGRect(x:block.bounds.minX * CGFloat(cg.width),y:block.bounds.minY * CGFloat(cg.height),width:block.bounds.width * CGFloat(cg.width),height:block.bounds.height * CGFloat(cg.height)).insetBy(dx:-3,dy:-2)
            NSColor.white.setFill(); bounds.fill()
            var size = min(42,max(7,bounds.height * 0.75))
            let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping
            var attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:size),.foregroundColor:NSColor.black,.paragraphStyle:paragraph]
            while size > 5 {
                let measured = (translated as NSString).boundingRect(with:CGSize(width:bounds.width,height:.greatestFiniteMagnitude),options:[.usesLineFragmentOrigin,.usesFontLeading],attributes:attrs)
                if measured.height <= bounds.height { break }
                size -= 0.5; attrs[.font] = NSFont.systemFont(ofSize:size)
            }
            (translated as NSString).draw(in:bounds,withAttributes:attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { throw NSError(domain:"ScreenshotKing",code:4,userInfo:[NSLocalizedDescriptionKey:"无法生成翻译图片"])}
        return NSImage(cgImage:result,size:image.size)
    }
}

@MainActor enum ImageIntelligence {
    private static var windows: [NSWindowController] = []
    private static var closeObservers:[ObjectIdentifier:NSObjectProtocol] = [:]
    static func show(image:NSImage,onImage:@escaping(NSImage)->Void) {
        let window: NSWindow
        if #available(macOS 15.0,*) {
            window = NSWindow(contentViewController:NSHostingController(rootView:ImageIntelligenceView(image:image,onImage:onImage)))
        } else {
            let label = NSTextField(wrappingLabelWithString:"图片翻译需要 macOS 15 或更新版本。可使用编辑器中的本地 OCR 提取文字。")
            label.frame = CGRect(x:20,y:20,width:400,height:80)
            window = NSWindow(contentRect:CGRect(x:0,y:0,width:440,height:120),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            window.contentView?.addSubview(label)
        }
        window.title = "文字、二维码与图片翻译"; window.isReleasedWhenClosed = false
        window.styleMask = [.titled,.closable,.resizable]; window.center()
        let controller = NSWindowController(window:window); windows.append(controller)
        let id = ObjectIdentifier(window)
        closeObservers[id] = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) { [weak window] _ in
            MainActor.assumeIsolated {
                window?.contentView = nil
                windows.removeAll { $0.window === window }
                if let observer = closeObservers.removeValue(forKey:id) { NotificationCenter.default.removeObserver(observer) }
            }
        }
        controller.showWindow(nil); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
}

@available(macOS 15.0,*)
@MainActor private struct ImageIntelligenceView: View {
    let image:NSImage
    let onImage:(NSImage)->Void
    @State private var blocks:[RecognizedBlock] = []
    @State private var codes:[String] = []
    @State private var source = ""
    @State private var translated = ""
    @State private var target = "zh-Hans"
    @State private var config:TranslationSession.Configuration?
    @State private var status = "正在本地识别…"
    @State private var busy = false
    @State private var translateImage = false
    var body:some View {
        VStack(spacing:12) {
            HSplitView {
                Image(nsImage:image).resizable().scaledToFit().frame(minWidth:260,minHeight:240).padding(12)
                VStack(alignment:.leading,spacing:8) {
                    Text("提取文字").font(.headline)
                    TextEditor(text:$source).font(.system(size:14)).frame(minHeight:150)
                    if !codes.isEmpty {
                        Text("二维码 / 条形码").font(.headline)
                        ForEach(Array(codes.enumerated()),id:\.offset) { code in Text(code.element).textSelection(.enabled).font(.callout) }
                    }
                    Text("译文").font(.headline)
                    TextEditor(text:$translated).font(.system(size:14)).frame(minHeight:120)
                }.padding(12).frame(minWidth:320)
            }
            Divider()
            HStack {
                Picker("目标语言",selection:$target) {
                    Text("简体中文").tag("zh-Hans");Text("English").tag("en");Text("日本語").tag("ja");Text("한국어").tag("ko");Text("Français").tag("fr");Text("Deutsch").tag("de");Text("Español").tag("es")
                }.frame(width:200)
                Button("复制文字") { copy(source) }.disabled(source.isEmpty)
                Button("翻译文字") { beginTranslation(image:false) }.disabled(busy || source.isEmpty)
                Button("翻译图片") { beginTranslation(image:true) }.disabled(busy || blocks.isEmpty)
                Button("复制译文") { copy(translated) }.disabled(translated.isEmpty)
            }.padding(.horizontal,12)
            Text(status).font(.callout).foregroundStyle(.secondary).frame(maxWidth:.infinity,alignment:.leading).padding([.horizontal,.bottom],12)
        }.frame(minWidth:850,minHeight:520)
        .task {
            guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { status = "无法读取图像";return }
            do {
                let result = try await Task.detached(priority:.userInitiated) { try ImageRecognition.read(cg) }.value
                blocks = result.blocks; codes = result.codes; source = blocks.map(\.text).joined(separator:"\n")
                status = "本地识别完成：\(blocks.count) 段文字，\(codes.count) 个码。翻译使用 Apple 翻译，首次可能需要下载语言。"
            } catch { status = "识别失败：\(error.localizedDescription)" }
        }
        .translationTask(config) { session in
            busy = true
            do {
                if translateImage {
                    let requests = blocks.enumerated().map { TranslationSession.Request(sourceText:$0.element.text,clientIdentifier:String($0.offset)) }
                    let responses = try await session.translations(from:requests)
                    let ordered = responses.sorted { Int($0.clientIdentifier!)! < Int($1.clientIdentifier!)! }.map(\.targetText)
                    translated = ordered.joined(separator:"\n")
                    let result = try ImageRecognition.renderTranslations(image:image,blocks:blocks,strings:ordered)
                    onImage(result); status = "翻译图片已送回编辑器，可以撤销。"
                } else {
                    translated = try await session.translate(source).targetText
                    status = "文字翻译完成。"
                }
            } catch { status = "翻译失败：\(error.localizedDescription)" }
            busy = false
        }
    }
    private func copy(_ text:String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType:.string) }
    private func beginTranslation(image:Bool) {
        translateImage = image
        if config?.target == Locale.Language(identifier:target) { config?.invalidate() }
        else { config = TranslationSession.Configuration(source:nil,target:Locale.Language(identifier:target)) }
        status = "正在请求 Apple 翻译…"
    }
}
