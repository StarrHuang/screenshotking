import AppKit
import Foundation

@MainActor
@main
struct ClipboardRuntimeMain {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardRuntime-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let board = NSPasteboard(name: NSPasteboard.Name("ClipboardRuntime-\(UUID().uuidString)"))
        let store = ClipboardStore(directory: root, pasteboard: board)
        store.startMonitoring()

        let text = NSPasteboardItem()
        text.setString("第一条", forType: .string)
        try write([text], to: board)
        store.checkPasteboardNow()
        try expect(store.items.count == 1 && store.items[0].plainText == "第一条", "文本采集")
        let originalHash = store.items[0].contentHash
        let duplicate = NSPasteboardItem()
        duplicate.setString("第一条", forType: .string)
        try write([duplicate], to: board)
        store.checkPasteboardNow()
        try expect(store.items.count == 1 && store.items[0].contentHash == originalHash, "稳定 hash 去重")
        print("PASS 文本采集与稳定 hash 去重")

        let fileA = fileItem("/tmp/甲.txt")
        let fileB = fileItem("/tmp/乙.txt")
        try write([fileA, fileB], to: board)
        store.checkPasteboardNow()
        let filesAB = try unwrap(store.items.first, "多文件捕获")
        try expect(filesAB.kind == .file && filesAB.pasteboardItems.count == 2, "保留多个 file pasteboard item")
        try expect(filesAB.preview == "甲.txt, 乙.txt", "文件顺序预览")
        _ = try store.restore(item: filesAB)
        let restoredAB = try unwrap(board.pasteboardItems, "恢复文件组")
        try expect(restoredAB.count == 2, "恢复多个 file pasteboard item")
        try expect(restoredAB.compactMap { $0.string(forType: .fileURL) } == [URL(fileURLWithPath: "/tmp/甲.txt").absoluteString, URL(fileURLWithPath: "/tmp/乙.txt").absoluteString], "保留文件顺序与 URL")
        try write([fileB, fileA], to: board)
        store.checkPasteboardNow()
        let filesBA = try unwrap(store.items.first, "反序多文件捕获")
        try expect(filesAB.contentHash != filesBA.contentHash, "hash 纳入 pasteboard item 顺序和边界")
        print("PASS 多文件分组、顺序、恢复与边界 hash")

        let imageA = imageItem([0x89, 0x50, 0x4e, 0x47, 1])
        let imageB = imageItem([0x89, 0x50, 0x4e, 0x47, 2])
        try write([imageA, imageB], to: board)
        store.checkPasteboardNow()
        let images = try unwrap(store.items.first, "多图片捕获")
        try expect(images.kind == .image && images.pasteboardItems.count == 2, "保留多张图片分组")
        _ = try store.restore(item: images)
        try expect(board.pasteboardItems?.count == 2, "恢复多张图片")
        print("PASS 多张图片分组和恢复")

        let rtf = NSPasteboardItem()
        let rtfText = NSAttributedString(string: "纯文本 RTF")
        guard let rtfData = rtfText.rtf(from: NSRange(location: 0, length: rtfText.length), documentAttributes: [:]) else {
            throw RuntimeFailure.assertion("生成 RTF 测试样本失败")
        }
        rtf.setData(rtfData, forType: .rtf)
        try write([rtf], to: board)
        store.checkPasteboardNow()
        let rtfEntry = try unwrap(store.items.first, "RTF 捕获")
        try expect(rtfEntry.plainText?.contains("纯文本 RTF") == true && rtfEntry.plainText?.contains("\\rtf") == false, "RTF 提取纯文本而非标记")

        let html = NSPasteboardItem()
        html.setData(Data("<html><body><p>HTML 纯文本</p></body></html>".utf8), forType: NSPasteboard.PasteboardType("public.html"))
        try write([html], to: board)
        store.checkPasteboardNow()
        let htmlEntry = try unwrap(store.items.first, "HTML 捕获")
        try expect(htmlEntry.plainText?.contains("HTML 纯文本") == true && htmlEntry.plainText?.contains("<p>") == false, "HTML 提取纯文本而非标签")
        print("PASS RTF / HTML 纯文本解析")

        board.clearContents()
        board.setString("失败时必须保留", forType: .string)
        let invalid = ClipboardEntry(id: UUID(), contentHash: "invalid", kind: .text, createdAt: Date(), lastUsedAt: Date(), preview: "", payloads: [], isFavorite: false, category: nil, tags: [])
        do {
            _ = try store.restore(item: invalid)
            throw RuntimeFailure.assertion("空记录恢复应该失败")
        } catch ClipboardStoreError.noRestorablePayload { }
        try expect(board.string(forType: .string) == "失败时必须保留", "校验失败不清空系统剪贴板")
        print("PASS 恢复校验失败保留原剪贴板")

        let textA = NSPasteboardItem()
        textA.setString("甲", forType: .string)
        let textB = NSPasteboardItem()
        textB.setString("乙", forType: .string)
        try write([textA], to: board); store.checkPasteboardNow()
        let entryA = try unwrap(store.items.first, "文本甲")
        try write([textB], to: board); store.checkPasteboardNow()
        let entryB = try unwrap(store.items.first, "文本乙")
        _ = try store.pasteBatch([entryA, entryB])
        try expect(board.string(forType: .string) == "甲\n乙", "批量复制用换行分隔")
        do {
            _ = try store.pasteBatch([entryA, images])
            throw RuntimeFailure.assertion("混合批量应该拒绝")
        } catch ClipboardStoreError.mixedBatchNotSupported { }
        try expect(board.string(forType: .string) == "甲\n乙", "混合批量拒绝前不改剪贴板")
        print("PASS 文本批量复制与混合类型保护")

        for marker in ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "com.example.password-field"] {
            let privateItem = NSPasteboardItem()
            privateItem.setString("隐私内容", forType: NSPasteboard.PasteboardType(marker))
            try write([privateItem], to: board)
            let count = store.items.count
            store.checkPasteboardNow()
            try expect(store.items.count == count, "排除隐私 UTI \(marker)")
        }
        print("PASS Concealed / Transient / password UTI 排除")

        store.setFavorite(true, id: filesAB.id)
        store.setCategory("工作", id: filesAB.id)
        store.addTag("项目", to: filesAB.id)
        store.cleanup(olderThan: 0, keepLimit: 0, confirmation: true)
        try expect(store.items.contains(where: { $0.id == filesAB.id }), "清理时收藏记录保留")
        try expect(store.filteredItems(favoritesOnly: true).allSatisfy(\.isFavorite), "收藏过滤")
        try expect(store.filteredItems(category: "工作").map(\.id) == [filesAB.id], "分类过滤")
        try expect(store.filteredItems(tag: "项目").map(\.id) == [filesAB.id], "标签过滤")
        print("PASS 收藏过滤与清理保护")

        let tooLarge = NSPasteboardItem()
        tooLarge.setData(Data(repeating: 7, count: ClipboardStore.maximumBytesPerPasteboardItem + 1), forType: NSPasteboard.PasteboardType("public.data"))
        try write([tooLarge], to: board)
        let count = store.items.count
        store.checkPasteboardNow()
        try expect(store.items.count == count && store.statusMessage?.contains("8 MB") == true, "单项超限时明确拒绝并提示，状态=\(store.statusMessage ?? "空")，记录数=\(store.items.count)")
        print("PASS 单项采集大小上限与状态提示")

        var totalOverflowItems = (0..<4).map { _ in imageItem(Array(repeating: 3, count: ClipboardStore.maximumBytesPerPasteboardItem)) }
        totalOverflowItems.append(imageItem([4]))
        try write(totalOverflowItems, to: board)
        let totalBefore = store.items.count
        store.checkPasteboardNow()
        try expect(store.items.count == totalBefore && store.statusMessage?.contains("32 MB") == true, "总量超限时明确拒绝并提示")
        print("PASS 单次采集总量上限与状态提示")

        store.stopMonitoring()
        let restoredStore = ClipboardStore(directory: root, pasteboard: board)
        try expect(restoredStore.items.contains(where: { $0.id == filesAB.id }), "本地历史持久化")
        try expect(restoredStore.moveToFrontAfterCopy == store.moveToFrontAfterCopy, "复制后移到最前设置持久化")
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(mode == 0o700, "私有数据目录权限 0700")
        let historyPath = root.appendingPathComponent("clipboard-history.json").path
        let historyAttributes = try FileManager.default.attributesOfItem(atPath: historyPath)
        let fileMode = (historyAttributes[.posixPermissions] as? NSNumber)?.intValue
        try expect(fileMode == 0o600, "历史文件权限 0600")
        print("PASS 本地持久化与 0700/0600 权限")

        print("RESULT all clipboard runtime checks passed; pasteboard=private named board; system clipboard untouched")
    }

    private static func fileItem(_ path: String) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
        return item
    }

    private static func imageItem(_ bytes: [UInt8]) -> NSPasteboardItem {
        let item = NSPasteboardItem()
        item.setData(Data(bytes), forType: NSPasteboard.PasteboardType("public.png"))
        return item
    }

    private static func write(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) throws {
        pasteboard.clearContents()
        let copies = items.map { source in
            let copy = NSPasteboardItem()
            for type in source.types {
                if let data = source.data(forType: type) { copy.setData(data, forType: type) }
                else if let string = source.string(forType: type) { copy.setString(string, forType: type) }
            }
            return copy
        }
        guard pasteboard.writeObjects(copies) else { throw RuntimeFailure.assertion("写入私有 NSPasteboard 失败") }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw RuntimeFailure.assertion(message) }
    }

    private static func unwrap<T>(_ value: T?, _ message: String) throws -> T {
        guard let value else { throw RuntimeFailure.assertion(message) }
        return value
    }
}

private enum RuntimeFailure: Error, CustomStringConvertible {
    case assertion(String)
    var description: String {
        switch self { case .assertion(let message): "FAIL \(message)" }
    }
}
