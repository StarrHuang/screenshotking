import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import Translation

@main @MainActor struct RecognitionRuntimeMain {
    static func main() async throws {
        _ = NSApplication.shared
        let width = 1000,height = 700
        let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor);context.fill(CGRect(x:0,y:0,width:width,height:height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext:context,flipped:false)
        ("ScreenshotKing QA" as NSString).draw(at:CGPoint(x:50,y:580),withAttributes:[.font:NSFont.boldSystemFont(ofSize:56),.foregroundColor:NSColor.black])
        ("Hello world. Capture 2026." as NSString).draw(at:CGPoint(x:50,y:480),withAttributes:[.font:NSFont.systemFont(ofSize:40),.foregroundColor:NSColor.black])
        NSColor.systemRed.setFill();CGRect(x:50,y:300,width:220,height:100).fill()
        NSColor.systemBlue.setFill();CGRect(x:50,y:60,width:220,height:100).fill()
        let qr = CIFilter.qrCodeGenerator();qr.message = Data("screenshotking://qa-fixture".utf8)
        let qrCG = CIContext().createCGImage(qr.outputImage!.transformed(by:CGAffineTransform(scaleX:8,y:8)),from:qr.outputImage!.extent.applying(CGAffineTransform(scaleX:8,y:8)))!
        context.interpolationQuality = .none;context.draw(qrCG,in:CGRect(x:650,y:80,width:240,height:240))
        NSGraphicsContext.restoreGraphicsState()
        let cg = context.makeImage()!
        let url = URL(fileURLWithPath:CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "evidence/qa-fixture.png")
        let destination = CGImageDestinationCreateWithURL(url as CFURL,"public.png" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,cg,nil);precondition(CGImageDestinationFinalize(destination))
        let result = try ImageRecognition.read(cg)
        let text = result.blocks.map(\.text).joined(separator:"\n")
        print("OCR:",text)
        precondition(text.contains("ScreenshotKing") && text.contains("Capture 2026"))
        precondition(result.codes.contains("screenshotking://qa-fixture"))
        let translated = try ImageRecognition.renderTranslations(image:NSImage(cgImage:cg,size:CGSize(width:500,height:350)),blocks:result.blocks,strings:result.blocks.map { _ in "本地图片翻译测试" })
        precondition(translated.cgImage(forProposedRect:nil,context:nil,hints:nil)!.width == width)
        let cleared = try ImageRecognition.renderTranslations(image:NSImage(cgImage:cg,size:CGSize(width:500,height:350)),blocks:result.blocks,strings:result.blocks.map { _ in "" })
        let clearedPixels = NSBitmapImageRep(cgImage:cleared.cgImage(forProposedRect:nil,context:nil,hints:nil)!)
        for block in result.blocks {
            let left = max(0,Int(block.bounds.minX * Double(width)))
            let right = min(width-1,Int(block.bounds.maxX * Double(width)))
            let top = max(0,Int((1-block.bounds.maxY) * Double(height)))
            let bottom = min(height-1,Int((1-block.bounds.minY) * Double(height)))
            for y in top...bottom { for x in left...right {
                let color = clearedPixels.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                precondition(color.redComponent > 0.995 && color.greenComponent > 0.995 && color.blueComponent > 0.995,"Original text must not show through the translation mask")
            } }
        }
        print("PASS OCR + QR + image translation overlay pixels and Retina dimensions")
        if #available(macOS 26.0,*) {
            let source = Locale.Language(identifier:"en"), target = Locale.Language(identifier:"zh-Hans")
            let status = await LanguageAvailability().status(from:source,to:target)
            print("Apple Translation en -> zh-Hans availability:",status)
            if status == .installed {
                let response = try await TranslationSession(installedSource:source,target:target).translate("Hello world")
                precondition(!response.targetText.isEmpty && response.targetText != "Hello world")
                print("PASS Apple Translation response:",response.targetText)
            } else { print("NOT_VERIFIED: Apple language model not installed; system UI download required") }
        }
    }
}
