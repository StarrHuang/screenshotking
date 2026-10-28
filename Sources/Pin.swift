import AppKit
import SwiftUI

@MainActor final class PinController: NSWindowController,NSWindowDelegate {
    let image: NSImage
    var onClose:(()->Void)?
    init(image: NSImage, frame:CGRect? = nil, scope:Int = 2, edit: @escaping (NSImage) -> Void) {
        self.image = image
        let panel = NSPanel(contentRect: CGRect(x: 200,y: 200,width: min(640,image.size.width),height: min(600,image.size.height + 42)), styleMask: [.titled,.closable,.resizable,.utilityWindow,.fullSizeContentView], backing: .buffered, defer: false)
        panel.title = L("钉图"); panel.level = scope == 0 ? .normal : .floating
        panel.isFloatingPanel = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = scope == 2 ? [.canJoinAllSpaces,.fullScreenAuxiliary] : [.fullScreenAuxiliary]
        if let frame { panel.setFrame(frame,display:false) }
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: PinView(image: image, reference: PinWindowReference(panel), edit: edit))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { showWindow(nil); window?.orderFrontRegardless() }
    func windowWillClose(_ notification:Notification) { window?.contentView = nil;onClose?() }
}

private final class PinWindowReference {
    weak var window:NSWindow?
    init(_ window:NSWindow) { self.window = window }
}

private struct PinView: View {
    let image: NSImage
    let reference: PinWindowReference
    let edit: (NSImage) -> Void
    @State var opacity = 1.0
    @State var collapsed = false
    @State var zoom = 1.0
    var body: some View {
        VStack(spacing: 0) {
            if !collapsed {
                Image(nsImage: image).resizable().scaledToFit().padding(4)
                    .scaleEffect(zoom).clipped()
                    .onTapGesture(count: 2) { collapsed.toggle() }
            }
            HStack(spacing: 10) {
                Button { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image]) } label: { Image(systemName: "doc.on.doc") }.help(L("复制图片"))
                Button { edit(image) } label: { Image(systemName: "pencil.tip.crop.circle") }.help(L("编辑"))
                Button { collapsed.toggle() } label: { Image(systemName: collapsed ? "arrow.down.right.and.arrow.up.left" : "minus") }.help(L("收起 / 展开"))
                Slider(value: $opacity, in: 0.15...1).frame(maxWidth: 110).help(L("透明度")).onChange(of: opacity) { _, value in reference.window?.alphaValue = value }
                Menu { Button("50%") { zoom = 0.5 }; Button("100%") { zoom = 1 }; Button("200%") { zoom = 2 } } label: { Image(systemName: "plus.magnifyingglass") }
                Button { reference.window?.close() } label: { Image(systemName: "xmark") }.help(L("关闭钉图"))
            }.buttonStyle(.borderless).padding(9).background(.regularMaterial)
        }.background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 240, minHeight: collapsed ? 42 : 120)
    }
}
