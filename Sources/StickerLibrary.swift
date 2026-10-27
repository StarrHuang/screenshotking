import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct StickerSelection: Codable, Equatable, Identifiable {
    public var id:String
    public var title:String
    public var text:String?
    public var pngData:Data?
}

private struct StickerCollection: Codable, Identifiable {
    var id = UUID().uuidString
    var name:String
    var items:[StickerSelection] = []
}

@MainActor private final class StickerStore: ObservableObject {
    @Published var collections:[StickerCollection] = []
    @Published var recent:[StickerSelection] = []
    @Published var error:String?
    private let url:URL
    private struct Archive:Codable { var collections:[StickerCollection];var recent:[StickerSelection] }
    init() {
        url = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("ScreenshotKing/stickers.json")
        if FileManager.default.fileExists(atPath:url.path) {
            do { let archive = try JSONDecoder().decode(Archive.self,from:Data(contentsOf:url));collections = archive.collections;recent = archive.recent }
            catch { self.error = "无法读取贴纸库：\(error.localizedDescription)" }
        }
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try JSONEncoder().encode(Archive(collections:collections,recent:recent)).write(to:url,options:.atomic)
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
        } catch { self.error = "无法保存贴纸库：\(error.localizedDescription)" }
    }
    func used(_ sticker:StickerSelection) { recent.removeAll { $0.id == sticker.id };recent.insert(sticker,at:0);recent = Array(recent.prefix(6));save() }
    func upload(to category:String) {
        let panel = NSOpenPanel();panel.allowedContentTypes = [.png,.jpeg,.heic,.tiff];panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var index = collections.firstIndex { $0.id == category }
        if index == nil { collections.append(StickerCollection(name:"我的贴纸"));index = collections.count-1 }
        for file in panel.urls {
            do {
                let data = try Data(contentsOf:file)
                guard data.count <= 20_000_000,let rep = NSBitmapImageRep(data:data),let png = rep.representation(using:.png,properties:[:]) else { throw CocoaError(.fileReadCorruptFile) }
                collections[index!].items.append(StickerSelection(id:UUID().uuidString,title:file.deletingPathExtension().lastPathComponent,pngData:png))
            } catch { self.error = "无法导入 \(file.lastPathComponent)：\(error.localizedDescription)" }
        }
        save()
    }
}

@MainActor public struct StickerPicker:View {
    @StateObject private var store = StickerStore()
    @State private var category = "symbols"
    @State private var search = ""
    @State private var newCategory = ""
    @State private var customEmoji = ""
    @State private var dragging:String?
    private let onSelect:(StickerSelection)->Void
    public init(onSelect:@escaping(StickerSelection)->Void) { self.onSelect = onSelect }
    private static let emoji:[(String,String)] = [("😀","笑脸"),("😁","开心"),("😂","笑哭"),("😊","微笑"),("😍","喜欢"),("🤔","思考"),("😎","酷"),("😢","哭"),("😡","生气"),("👍","赞"),("👎","踩"),("👏","鼓掌"),("🙏","谢谢"),("💪","加油"),("👀","查看"),("👉","指向"),("✅","对勾"),("❌","错误"),("⚠️","警告"),("❓","疑问"),("💡","灵感"),("🔥","热门"),("❤️","爱心"),("⭐️","星星"),("🚩","旗帜"),("🎉","庆祝"),("🐱","猫"),("🌲","树"),("🍎","苹果"),("✈️","飞机"),("🏠","家"),("📷","相机"),("🔒","锁"),("🔍","搜索"),("📌","图钉"),("💯","满分")]
    private static let symbols:[(String,String)] = [("checkmark.circle.fill","对勾"),("xmark.circle.fill","错误"),("exclamationmark.triangle.fill","警告"),("info.circle.fill","信息"),("questionmark.circle.fill","疑问"),("star.fill","星标"),("heart.fill","爱心"),("flag.fill","旗帜"),("pin.fill","图钉"),("lightbulb.fill","灯泡"),("lock.fill","锁"),("shield.fill","盾牌"),("hand.tap.fill","点击"),("cursorarrow","鼠标指针"),("viewfinder","聚焦框"),("exclamationmark.circle.fill","注意"),("arrow.left","向左"),("arrow.right","向右"),("arrow.up","向上"),("arrow.down","向下"),("hand.draw.fill","拖拽"),("hand.point.up.left.fill","滑动")]
    private var items:[StickerSelection] {
        let list:[StickerSelection]
        if category == "emoji" { list = Self.emoji.map { StickerSelection(id:"emoji-\($0.0)",title:$0.1,text:$0.0) } }
        else if category == "symbols" { list = Self.symbols.compactMap { symbol,title in
            guard let image = NSImage(systemSymbolName:symbol,accessibilityDescription:title)?.withSymbolConfiguration(.init(pointSize:100,weight:.semibold)),let tiff = image.tiffRepresentation,let rep = NSBitmapImageRep(data:tiff),let data = rep.representation(using:.png,properties:[:]) else { return nil }
            return StickerSelection(id:"symbol-\(symbol)",title:title,pngData:data)
        } } else { list = store.collections.first { $0.id == category }?.items ?? [] }
        return list.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || ($0.text?.contains(search) ?? false) }
    }
    public var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack { Text("贴纸").font(.title2.bold());Spacer();Button("上传图片") { store.upload(to:category) } }
            TextField("搜索贴纸或表情",text:$search).textFieldStyle(.roundedBorder)
            if category == "emoji" { HStack {
                TextField("输入任意表情",text:$customEmoji).textFieldStyle(.roundedBorder)
                Button("系统全部表情") { NSApp.orderFrontCharacterPalette(nil) }
                Button("使用") { let item = StickerSelection(id:"emoji-\(customEmoji)",title:customEmoji,text:customEmoji);store.used(item);onSelect(item) }.disabled(customEmoji.isEmpty)
            } }
            if !store.recent.isEmpty {
                Text("最近使用 · 按 1–6 插入").font(.caption).foregroundStyle(.secondary)
                HStack { ForEach(Array(store.recent.enumerated()),id:\.element.id) { index,item in
                    stickerButton(item).keyboardShortcut(KeyEquivalent(Character(String(index+1))),modifiers:[])
                } }
            }
            ScrollView(.horizontal) { HStack {
                Button("标注") { category = "symbols" }.tint(category == "symbols" ? .accentColor : nil)
                Button("Emoji") { category = "emoji" }.tint(category == "emoji" ? .accentColor : nil)
                ForEach(store.collections) { collection in
                    Button(collection.name) { category = collection.id }.tint(category == collection.id ? .accentColor : nil)
                        .onDrag { dragging = collection.id;return NSItemProvider(object:collection.id as NSString) }
                        .onDrop(of:[.text],isTargeted:nil) { _ in
                            guard let dragging,let from = store.collections.firstIndex(where:{$0.id == dragging}),let to = store.collections.firstIndex(where:{$0.id == collection.id}) else { return false }
                            store.collections.move(fromOffsets:IndexSet(integer:from),toOffset:to > from ? to+1 : to);store.save();self.dragging = nil;return true
                        }
                }
            }.buttonStyle(.bordered) }
            ScrollView { LazyVGrid(columns:[GridItem(.adaptive(minimum:68))],spacing:10) { ForEach(items) { stickerButton($0) } } }.frame(minHeight:210)
            HStack {
                TextField("新分类名称",text:$newCategory).textFieldStyle(.roundedBorder)
                Button("添加分类") { let name = newCategory.trimmingCharacters(in:.whitespacesAndNewlines);if !name.isEmpty { let collection = StickerCollection(name:name);store.collections.append(collection);category = collection.id;newCategory = "";store.save() } }.disabled(newCategory.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
            }
            if let index = store.collections.firstIndex(where:{$0.id == category}) {
                HStack { TextField("分类名称",text:Binding(get:{store.collections[index].name},set:{store.collections[index].name = $0;store.save()})).textFieldStyle(.roundedBorder)
                    Text("拖动分类调整顺序").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = store.error { Text(error).foregroundStyle(.red).font(.caption).textSelection(.enabled) }
        }.padding(18).frame(width:540,height:480)
    }
    private func stickerButton(_ item:StickerSelection)->some View {
        Button { store.used(item);onSelect(item) } label: {
            VStack(spacing:4) {
                if let text = item.text { Text(text).font(.system(size:32)).frame(height:42) }
                else if let data = item.pngData,let image = NSImage(data:data) { Image(nsImage:image).resizable().scaledToFit().frame(width:42,height:42) }
                Text(item.title).font(.caption2).lineLimit(1)
            }.frame(width:66,height:64)
        }.buttonStyle(.plain).help(item.title)
    }
}
