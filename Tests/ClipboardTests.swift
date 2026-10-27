import AppKit
import XCTest
@testable import ScreenshotKing

@MainActor
final class ClipboardTests: XCTestCase {
    private func makeStore() -> (ClipboardStore, NSPasteboard, URL) {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipboardTests-\(UUID().uuidString)"))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardTests-\(UUID().uuidString)", isDirectory: true)
        return (ClipboardStore(directory: directory, pasteboard: pasteboard), pasteboard, directory)
    }

    private func put(_ string: String, on pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func testCapturesDeduplicatesAndStopsWhenPaused() throws {
        let (store, pasteboard, _) = makeStore()
        store.startMonitoring()
        put("first", on: pasteboard)
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].preview, "first")

        put("first", on: pasteboard)
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.count, 1, "Equal normalized formats should have a stable content hash.")

        store.stopMonitoring()
        put("second", on: pasteboard)
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.isMonitoring)
    }

    func testRichTextRoundTripsOriginalPasteboardFormats() throws {
        let (store, pasteboard, _) = makeStore()
        let boardItem = NSPasteboardItem()
        let rtf = Data("{\\rtf1\\ansi rich}".utf8)
        boardItem.setString("rich", forType: .string)
        boardItem.setData(rtf, forType: .rtf)
        pasteboard.clearContents()
        pasteboard.writeObjects([boardItem])

        store.startMonitoring()
        store.checkPasteboardNow()
        let entry = try XCTUnwrap(store.items.first)
        XCTAssertEqual(entry.kind, .richText)
        _ = try store.restore(item: entry)

        let restored = try XCTUnwrap(pasteboard.pasteboardItems?.first)
        XCTAssertEqual(restored.string(forType: .string), "rich")
        XCTAssertEqual(restored.data(forType: .rtf), rtf)
    }

    func testPreservesMultiplePasteboardItemsAndTheirOrder() throws {
        let (store, pasteboard, _) = makeStore()
        let first = NSPasteboardItem()
        first.setString(URL(fileURLWithPath: "/tmp/first.txt").absoluteString, forType: .fileURL)
        let second = NSPasteboardItem()
        second.setString(URL(fileURLWithPath: "/tmp/second.txt").absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([first, second])
        store.startMonitoring()
        store.checkPasteboardNow()
        let captured = try XCTUnwrap(store.items.first)
        XCTAssertEqual(captured.pasteboardItems.count, 2)
        XCTAssertEqual(captured.preview, "first.txt, second.txt")

        _ = try store.restore(item: captured)
        XCTAssertEqual(pasteboard.pasteboardItems?.compactMap { $0.string(forType: .fileURL) }, [
            URL(fileURLWithPath: "/tmp/first.txt").absoluteString,
            URL(fileURLWithPath: "/tmp/second.txt").absoluteString
        ])
    }

    func testRTFAndHTMLPlainTextWithoutPlainStringFormat() throws {
        let (store, pasteboard, _) = makeStore()
        let rtf = NSPasteboardItem()
        let richText = NSAttributedString(string: "纯文本 RTF")
        let rtfData = try XCTUnwrap(richText.rtf(from: NSRange(location: 0, length: richText.length), documentAttributes: [:]))
        rtf.setData(rtfData, forType: .rtf)
        pasteboard.clearContents()
        pasteboard.writeObjects([rtf])
        store.startMonitoring()
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.first?.plainText, "纯文本 RTF")

        let html = NSPasteboardItem()
        html.setData(Data("<meta charset=\"utf-8\"><p>HTML 纯文本</p>".utf8), forType: NSPasteboard.PasteboardType("public.html"))
        pasteboard.clearContents()
        pasteboard.writeObjects([html])
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.first?.plainText?.contains("HTML 纯文本"), true)
        XCTAssertEqual(store.items.first?.plainText?.contains("<p>"), false)
    }

    func testRestoreValidationFailureLeavesPasteboardUntouched() throws {
        let (store, pasteboard, _) = makeStore()
        pasteboard.clearContents()
        pasteboard.setString("keep this", forType: .string)
        let invalid = ClipboardEntry(id: UUID(), contentHash: "empty", kind: .text, createdAt: Date(), lastUsedAt: Date(), preview: "", payloads: [], isFavorite: false, category: nil, tags: [])
        XCTAssertThrowsError(try store.restore(item: invalid))
        XCTAssertEqual(pasteboard.string(forType: .string), "keep this")
    }

    func testCategorizesImageAndFileURLPayloads() throws {
        let (store, pasteboard, _) = makeStore()
        let image = NSPasteboardItem()
        image.setData(Data([0x89, 0x50, 0x4e, 0x47]), forType: NSPasteboard.PasteboardType("public.png"))
        pasteboard.clearContents()
        pasteboard.writeObjects([image])
        store.startMonitoring()
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.first?.kind, .image)

        let file = NSPasteboardItem()
        file.setString(URL(fileURLWithPath: "/tmp/report.txt").absoluteString, forType: .fileURL)
        pasteboard.clearContents()
        pasteboard.writeObjects([file])
        store.checkPasteboardNow()
        XCTAssertEqual(store.items.first?.kind, .file)
        XCTAssertEqual(store.items.first?.preview, "report.txt")
    }

    func testExcludesTransientConcealedAndPasswordTypes() {
        let (store, pasteboard, _) = makeStore()
        store.startMonitoring()
        let concealed = NSPasteboardItem()
        concealed.setData(Data([1]), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.clearContents()
        pasteboard.writeObjects([concealed])
        store.checkPasteboardNow()
        XCTAssertTrue(store.items.isEmpty)

        let password = NSPasteboardItem()
        password.setString("secret", forType: NSPasteboard.PasteboardType("com.example.password-field"))
        pasteboard.clearContents()
        pasteboard.writeObjects([password])
        store.checkPasteboardNow()
        XCTAssertTrue(store.items.isEmpty)

        let transient = NSPasteboardItem()
        transient.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        transient.setString("private", forType: .string)
        pasteboard.clearContents()
        pasteboard.writeObjects([transient])
        store.checkPasteboardNow()
        XCTAssertTrue(store.items.isEmpty)
    }

    func testFavoritesSurviveCleanupAndCategoryDeletionKeepsRecord() throws {
        let (store, pasteboard, _) = makeStore()
        store.startMonitoring()
        put("keep me", on: pasteboard)
        store.checkPasteboardNow()
        let entry = try XCTUnwrap(store.items.first)
        store.setFavorite(true, id: entry.id)
        store.setCategory(store.createCategory("Reference"), id: entry.id)
        store.addTag("work", to: entry.id)
        store.deleteCategory("Reference")
        store.cleanup(olderThan: 0, keepLimit: 0, confirmation: true)
        XCTAssertEqual(store.items.count, 1)
        XCTAssertTrue(store.items[0].isFavorite)
        XCTAssertNil(store.items[0].category)
        XCTAssertEqual(store.items[0].tags, ["work"])
        store.deleteTag("work")
        XCTAssertTrue(store.items[0].tags.isEmpty)
    }

    func testPersistsAndExportsThenImportsOnlyWithConfirmation() throws {
        let (store, pasteboard, directory) = makeStore()
        store.startMonitoring()
        put("persistent", on: pasteboard)
        store.checkPasteboardNow()
        let entry = try XCTUnwrap(store.items.first)
        store.setFavorite(true, id: entry.id)

        let reloaded = ClipboardStore(directory: directory, pasteboard: pasteboard)
        XCTAssertEqual(reloaded.items.map(\.contentHash), [entry.contentHash])

        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("ClipboardBackup-\(UUID().uuidString).json")
        try store.exportBackup(to: backup)
        let (destination, _, _) = makeStore()
        try destination.importBackup(from: backup, confirmation: false)
        XCTAssertTrue(destination.items.isEmpty)
        try destination.importBackup(from: backup, confirmation: true)
        XCTAssertEqual(destination.items.map(\.contentHash), [entry.contentHash])
    }

    func testBatchPasteRequiresTextAndJoinsWithNewline() throws {
        let (store, pasteboard, _) = makeStore()
        store.startMonitoring()
        put("one", on: pasteboard)
        store.checkPasteboardNow()
        let first = try XCTUnwrap(store.items.first)
        put("two", on: pasteboard)
        store.checkPasteboardNow()
        let second = try XCTUnwrap(store.items.first(where: { $0.preview == "two" }))
        _ = try store.pasteBatch([first, second])
        XCTAssertEqual(pasteboard.string(forType: .string), "one\ntwo")

        let image = ClipboardEntry(id: UUID(), contentHash: "image", kind: .image, createdAt: Date(), lastUsedAt: Date(), preview: "Image", payloads: [.init(type: "public.png", data: Data([1]))], isFavorite: false, category: nil, tags: [])
        XCTAssertThrowsError(try store.pasteBatch([first, image]))
    }
}
