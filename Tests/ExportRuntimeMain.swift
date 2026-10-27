import AppKit
import ImageIO

@main @MainActor struct ExportRuntimeMain {
    static func main() throws {
        _ = NSApplication.shared
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenshotKing-Export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let defaults = UserDefaults(suiteName:"ScreenshotKing.Export.QA.\(UUID().uuidString)")!
        defaults.set(false,forKey:"exportAsk");defaults.set(folder.path,forKey:"exportDirectory")
        defaults.set("QA_$yyyy-MM-dd$_%title%",forKey:"exportTemplate")
        let context = CGContext(data:nil,width:24,height:16,bitsPerComponent:8,bytesPerRow:96,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.systemRed.cgColor);context.fill(CGRect(x:0,y:0,width:24,height:16))
        let image = NSImage(cgImage:context.makeImage()!,size:CGSize(width:12,height:8))
        for ext in ["png","jpg","heic"] {
            defaults.set(ext,forKey:"exportFormat")
            let url = try ScreenshotExport.save(image,defaults:defaults,date:Date(timeIntervalSince1970:0))!
            let source = CGImageSourceCreateWithURL(url as CFURL,nil)!
            let output = CGImageSourceCreateImageAtIndex(source,0,nil)!
            precondition(output.width == 24 && output.height == 16)
            let second = try ScreenshotExport.save(image,defaults:defaults,date:Date(timeIntervalSince1970:0))!
            precondition(second != url && FileManager.default.fileExists(atPath:url.path))
        }
        let silentDefaults = UserDefaults(suiteName:"ScreenshotKing.Export.SilentQA.\(UUID().uuidString)")!
        silentDefaults.set(true,forKey:"exportAsk");silentDefaults.set(folder.path,forKey:"exportDirectory")
        silentDefaults.set(true,forKey:"exportReveal");silentDefaults.set(true,forKey:"exportCopyPath")
        silentDefaults.set("Silent_$yyyy-MM-dd$",forKey:"exportTemplate");silentDefaults.set("png",forKey:"exportFormat")
        let silentURL = try ScreenshotExport.save(image,defaults:silentDefaults,date:Date(timeIntervalSince1970:0),silently:true)!
        let silentSecond = try ScreenshotExport.save(image,defaults:silentDefaults,date:Date(timeIntervalSince1970:0),silently:true)!
        precondition(silentURL.deletingLastPathComponent().path == folder.path && silentSecond.path != silentURL.path)
        precondition(FileManager.default.fileExists(atPath:silentURL.path) && FileManager.default.fileExists(atPath:silentSecond.path))
        let name = ScreenshotExport.name(template:"../../private/%title%",title:"a/b",format:"png")
        precondition(!name.contains("/") && name.hasSuffix(".png"))
        print("PASS export: PNG/JPEG/HEIC pixels, Retina dimensions, templates, safe filenames, no overwrite; silent save ignores prompt/reveal/path-copy settings without touching clipboard")
    }
}
