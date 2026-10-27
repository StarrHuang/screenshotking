import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct ClipboardRootView: View {
    @ObservedObject private var store: ClipboardStore
    private let onPin: (NSImage) -> Void
    @State private var query = ""
    @State private var selectedIDs = Set<UUID>()
    @State private var selectedKind: ClipboardContentKind?
    @State private var favoritesOnly = false
    @State private var selectedCategory: String?
    @State private var selectedTag: String?
    @State private var showCleanupConfirmation = false
    @State private var showImportConfirmation = false
    @State private var importURL: URL?
    @State private var showSettings = false
    @State private var actionError: String?
    @State private var categoryDraft = ""
    @State private var tagDraft = ""

    public init(store: ClipboardStore, onPin: @escaping (NSImage) -> Void = { _ in }) {
        self.store = store
        self.onPin = onPin
    }

    private var visibleItems: [ClipboardEntry] {
        store.filteredItems(search: query, kind: selectedKind, favoritesOnly: favoritesOnly, category: selectedCategory, tag: selectedTag)
    }

    private var selectedItem: ClipboardEntry? {
        visibleItems.first(where: { selectedIDs.contains($0.id) }) ?? visibleItems.first
    }

    private var orderedSelection: [ClipboardEntry] {
        visibleItems.filter { selectedIDs.contains($0.id) }
    }

    public var body: some View {
        NavigationSplitView {
            sidebar
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
            .toolbar { toolbarContent }
        } detail: {
            detailView
        }
        .frame(minWidth: 760, minHeight: 500)
        .confirmationDialog("选择要删除的记录。此操作无法撤销。", isPresented: $showCleanupConfirmation) { cleanupActions }
        .confirmationDialog("导入此剪贴板备份？相同内容会跳过。", isPresented: $showImportConfirmation) { importActions }
        .sheet(isPresented: $showSettings) { settingsView }
        .onKeyPress(characters: .decimalDigits, phases: .down) { key in
            guard key.modifiers == .option, let number = Int(key.characters), (1...9).contains(number) else { return .ignored }
            runAction { _ = try store.performNumericShortcut(number, among: visibleItems) }
            return .handled
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            searchField
            filterControls
            itemList
            selectionAction
            monitorStatus
        }
        .padding(12)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索剪贴板", text: $query).textFieldStyle(.plain)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("类型", selection: $selectedKind) {
                Text("全部类型").tag(Optional<ClipboardContentKind>.none)
                ForEach(ClipboardContentKind.allCases) { kind in Text(kind.title).tag(Optional(kind)) }
            }
            .pickerStyle(.menu)
            Toggle("只看收藏", isOn: $favoritesOnly).toggleStyle(.checkbox)
            HStack {
                Menu(selectedCategory ?? "全部分类") {
                    Button("全部分类") { selectedCategory = nil }
                    ForEach(store.categories, id: \.self) { category in Button(category) { selectedCategory = category } }
                }
                Menu(selectedTag ?? "全部标签") {
                    Button("全部标签") { selectedTag = nil }
                    ForEach(store.tags, id: \.self) { tag in Button(tag) { selectedTag = tag } }
                }
            }
        }
    }

    private var itemList: some View {
        List(selection: $selectedIDs) {
            ForEach(visibleItems) { item in clipboardRow(item) }
        }
        .listStyle(.plain)
    }

    private func clipboardRow(_ item: ClipboardEntry) -> some View {
        ClipboardRow(item: item)
            .onTapGesture(count: 1) {
                selectedIDs.insert(item.id)
                switch store.selectionBehavior {
                case .clickCopiesDoubleClickPastes: runAction { _ = try store.restore(item: item) }
                case .clickPastes: runAction { _ = try store.paste(item: item) }
                case .doubleClickPastes: break
                }
            }
            .onTapGesture(count: 2) {
                selectedIDs.insert(item.id)
                if store.selectionBehavior != .clickPastes {
                    runAction { _ = try store.paste(item: item) }
                }
            }
            .tag(item.id)
            .contextMenu {
                Button("复制原格式") { runAction { _ = try store.restore(item: item) } }
                Button("复制为纯文本") { runAction { _ = try store.restore(item: item, plainText: true) } }
                Button(item.isFavorite ? "取消收藏" : "添加收藏") { store.toggleFavorite(id: item.id) }
                if let image = store.image(for: item) { Button("钉住图片") { onPin(image) } }
                Divider()
                Button("删除记录", role: .destructive) { store.remove(id: item.id, confirmation: true) }
            }
    }

    @ViewBuilder
    private var selectionAction: some View {
        if orderedSelection.count > 1 {
            Button("批量复制所选文本（以换行分隔）") { runAction { _ = try store.pasteBatch(orderedSelection) } }
                .disabled(orderedSelection.contains(where: { $0.kind != .text && $0.kind != .richText }))
        }
    }

    private var monitorStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Circle().fill(store.isMonitoring ? .green : .gray).frame(width: 7, height: 7)
                Text(store.isMonitoring ? "正在监听" : "已暂停").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(store.isMonitoring ? "暂停" : "继续") {
                    store.isMonitoring ? store.stopMonitoring() : store.startMonitoring()
                }
                .controlSize(.small)
            }
            if let message = store.errorMessage ?? store.statusMessage {
                Label(message, systemImage: store.errorMessage == nil ? "info.circle" : "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(store.errorMessage == nil ? Color.secondary : Color.orange)
                    .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button { showCleanupConfirmation = true } label: { Image(systemName: "trash") }.help("清理记录")
        }
        ToolbarItem {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }.help("剪贴板设置")
        }
        ToolbarItem {
            Menu {
                Button("导出本地备份…", systemImage: "square.and.arrow.up") { exportBackup() }
                Button("导入本地备份…", systemImage: "square.and.arrow.down") { chooseBackupToImport() }
            } label: { Image(systemName: "ellipsis.circle") }.help("剪贴板备份")
        }
    }

    @ViewBuilder
    private var cleanupActions: some View {
        Button("删除非收藏文本") { store.clearMatching(kinds: [.text, .richText], favorite: false, confirmation: true) }
        Button("删除收藏文本") { store.clearMatching(kinds: [.text, .richText], favorite: true, confirmation: true) }
        Button("删除非收藏图片") { store.clearMatching(kinds: [.image], favorite: false, confirmation: true) }
        Button("删除收藏图片") { store.clearMatching(kinds: [.image], favorite: true, confirmation: true) }
        Button("删除全部非收藏记录") { store.clearMatching(favorite: false, confirmation: true) }
        Button("删除全部收藏记录", role: .destructive) { store.clearMatching(favorite: true, confirmation: true) }
        Button("取消", role: .cancel) { }
    }

    @ViewBuilder
    private var importActions: some View {
        Button("导入备份", role: .destructive) {
            guard let importURL else { return }
            runAction { try store.importBackup(from: importURL, confirmation: true) }
            self.importURL = nil
        }
        Button("取消", role: .cancel) { importURL = nil }
    }

    private var settingsView: some View {
        Form {
            Picker("单击 / 双击", selection: $store.selectionBehavior) {
                Text("单击复制；双击发送粘贴请求").tag(ClipboardSelectionBehavior.clickCopiesDoubleClickPastes)
                Text("单击发送粘贴请求").tag(ClipboardSelectionBehavior.clickPastes)
                Text("单击选中；双击发送粘贴请求").tag(ClipboardSelectionBehavior.doubleClickPastes)
            }
            Picker("Option + 数字键 1–9", selection: $store.numericKeyBehavior) {
                Text("关闭").tag(ClipboardNumericKeyBehavior.disabled)
                Text("复制对应记录").tag(ClipboardNumericKeyBehavior.copy)
                Text("发送粘贴请求").tag(ClipboardNumericKeyBehavior.paste)
            }
            Toggle("复制使用后移到最前", isOn: $store.moveToFrontAfterCopy)
            Stepper("保留 \(store.retentionDays) 天", value: $store.retentionDays, in: 1...365)
            Stepper("最多保存 \(store.itemCountLimit) 条", value: $store.itemCountLimit, in: 50...5000, step: 50)
            HStack { Spacer(); Button("完成") { showSettings = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(20)
        .frame(width: 420)
    }

    @ViewBuilder
    private var detailView: some View {
        if let item = selectedItem {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.kind.title).font(.headline)
                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        store.toggleFavorite(id: item.id)
                    } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                    }
                    .buttonStyle(.borderless)
                    .help(item.isFavorite ? "取消收藏" : "收藏")
                }

                if let image = store.image(for: item) {
                    Image(nsImage: image)
                        .resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 300)
                        .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    ScrollView {
                        Text(item.preview.isEmpty ? "没有可预览内容" : item.preview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                }

                HStack {
                    Button("复制") { runAction { _ = try store.restore(item: item) } }
                    Button("纯文本") { runAction { _ = try store.restore(item: item, plainText: true) } }
                    Button("粘贴到 \(store.previousApplicationName ?? "上一个应用")") { runAction { _ = try store.paste(item: item) } }
                    if let image = store.image(for: item) {
                        Button("钉图") { onPin(image) }
                        Button("保存图片…") { saveImage(item) }
                    }
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.byteCount), countStyle: .file))
                        .font(.caption).foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("分类").font(.caption).foregroundStyle(.secondary)
                        Menu(item.category ?? "选择分类") {
                            Button("无分类") { store.setCategory(nil, id: item.id) }
                            ForEach(store.categories, id: \.self) { category in
                                Button(category) { store.setCategory(category, id: item.id) }
                            }
                            if !store.categories.isEmpty {
                                Menu("删除分类") {
                                    ForEach(store.categories, id: \.self) { category in
                                        Button(category, role: .destructive) { store.deleteCategory(category) }
                                    }
                                }
                            }
                        }
                        TextField("新建分类", text: $categoryDraft)
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        Button("添加") {
                            if let category = store.createCategory(categoryDraft) {
                                store.setCategory(category, id: item.id)
                                categoryDraft = ""
                            }
                        }
                        .disabled(categoryDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        Text("标签").font(.caption).foregroundStyle(.secondary)
                        Text(item.tags.joined(separator: ", ")).lineLimit(1).foregroundStyle(.secondary)
                        TextField("添加标签", text: $tagDraft).textFieldStyle(.roundedBorder).frame(maxWidth: 180)
                        Button("添加") { store.addTag(tagDraft, to: item.id); tagDraft = "" }
                            .disabled(tagDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        ForEach(item.tags, id: \.self) { tag in
                            Button { store.removeTag(tag, from: item.id) } label: { Image(systemName: "xmark.circle") }
                                .buttonStyle(.plain).help("移除标签 \(tag)")
                        }
                    }
                }

                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let actionError {
                    Label(actionError, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
                if let status = store.statusMessage {
                    Label(status, systemImage: "info.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
        } else {
            ContentUnavailableView("暂无剪贴记录", systemImage: "doc.on.clipboard", description: Text("开启监听后复制内容即可记录。"))
        }
    }

    private func saveImage(_ item: ClipboardEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "剪贴图片.png"
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.saveImage(item: item, to: url)
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func exportBackup() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "剪贴板备份.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        runAction { try store.exportBackup(to: url) }
    }

    private func chooseBackupToImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importURL = url
        showImportConfirmation = true
    }

    private func runAction(_ action: () throws -> Void) {
        do {
            try action()
            actionError = nil
        } catch {
            actionError = error.localizedDescription
        }
    }
}

private struct ClipboardRow: View {
    let item: ClipboardEntry

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.preview.isEmpty ? item.kind.title : item.preview.replacingOccurrences(of: "\n", with: " "))
                    .lineLimit(2).font(.system(size: 13))
                HStack(spacing: 6) {
                    Text(item.createdAt.formatted(date: .omitted, time: .shortened))
                    if let category = item.category { Text("· \(category)") }
                    if !item.tags.isEmpty { Text("· \(item.tags.joined(separator: ", "))").lineLimit(1) }
                }
                .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
            if item.isFavorite { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var icon: String {
        switch item.kind {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .image: "photo"
        case .file: "doc"
        case .other: "clipboard"
        }
    }
}

@MainActor
public final class ClipboardWindow: NSWindowController {
    public convenience init(store: ClipboardStore, onPin: @escaping (NSImage) -> Void = { _ in }) {
        let root = ClipboardRootView(store: store, onPin: onPin)
        let window = NSWindow(contentViewController: NSHostingController(rootView: root))
        window.title = "ScreenshotKing 剪贴板"
        window.setContentSize(NSSize(width: 900, height: 620))
        window.minSize = NSSize(width: 760, height: 500)
        window.center()
        window.isReleasedWhenClosed = false
        self.init(window: window)
    }

    public func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
