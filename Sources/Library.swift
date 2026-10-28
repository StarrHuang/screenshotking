import AppKit
import SwiftUI

struct LibraryEntry: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
}

@MainActor final class CaptureLibrary: ObservableObject {
    @Published var entries: [LibraryEntry] = []
    @Published var error: String?
    let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ScreenshotKing/Captures", isDirectory: true)
        reload()
    }
    func reload() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]).filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent > $1.lastPathComponent }.map { LibraryEntry(url: $0) }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func add(_ image: NSImage) throws -> URL {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "ScreenshotKing", code: 1, userInfo: [NSLocalizedDescriptionKey:L("无法编码截图")])
        }
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        let file = directory.appendingPathComponent("ScreenshotKing_\(formatter.string(from: Date()))_\(UUID().uuidString.prefix(6)).png")
        try png.write(to: file, options: [.atomic]); reload()
        return file.deletingPathExtension().appendingPathExtension("skedit")
    }
}

@MainActor struct LibraryView: View {
    @ObservedObject var library: CaptureLibrary
    var open: (NSImage, URL) -> Void
    @State private var query = ""
    var body: some View {
        VStack {
            HStack { Text(L("截图库")).font(.title2.bold()); Spacer(); Button(L("在 Finder 中打开")) { NSWorkspace.shared.open(library.directory) } }.padding()
            if let error = library.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190))], spacing: 18) {
                    ForEach(library.entries.filter { query.isEmpty || $0.id.localizedCaseInsensitiveContains(query) }) { entry in
                        if let image = NSImage(contentsOf: entry.url) {
                            Button { open(image, entry.url.deletingPathExtension().appendingPathExtension("skedit")) } label: {
                                VStack(alignment: .leading) {
                                    Image(nsImage: image).resizable().scaledToFit().frame(height: 135)
                                    Text(entry.id).font(.caption).lineLimit(2)
                                }.padding(10).frame(maxWidth: .infinity).background(Color(nsColor: .controlBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).help(L("打开编辑"))
                        }
                    }
                }.padding()
                if library.entries.isEmpty { Text(L("截图后，图片会出现在这里。")).foregroundStyle(.secondary).padding(50) }
            }
        }.searchable(text: $query, prompt: L("按文件名搜索")).frame(minWidth: 650,minHeight: 420).onAppear { library.reload() }
    }
}
