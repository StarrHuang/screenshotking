import AppKit
import SwiftUI

@MainActor final class InlineCaptureEditor:NSWindowController,NSWindowDelegate {
    var onClose:(()->Void)?
    private var closed = false
    init(selection:CaptureSelection,documentURL:URL?,onPin:@escaping(NSImage)->Void,onCopy:@escaping(NSImage)->Void) {
        let screen = selection.target.screen
        let panel = InlineEditorPanel(contentRect:screen.frame,styleMask:[.borderless],backing:.buffered,defer:false)
        panel.level = .screenSaver;panel.hasShadow = false;panel.isOpaque = true
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        super.init(window:panel)
        panel.delegate = self
        let rect = CGRect(x:selection.rect.minX,y:screen.frame.height-selection.rect.maxY,width:selection.rect.width,height:selection.rect.height)
        let background = NSImage(cgImage:selection.target.image,size:screen.frame.size)
        let root = ZStack {
            Image(nsImage:background).resizable().frame(width:screen.frame.width,height:screen.frame.height)
            Color.black.opacity(0.42)
            ImageEditorContent(image:selection.image!,documentURL:documentURL,presentation:.inline,inlineImageFrame:rect,onPin:{ [weak self] image in self?.close();onPin(image) },onCopy:{ [weak self] image in self?.close();onCopy(image) },onClose:{ [weak self] in self?.close() })
        }.frame(width:screen.frame.width,height:screen.frame.height)
        panel.contentView = NSHostingView(rootView:root)
    }
    required init?(coder:NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show() { window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true) }
    func windowWillClose(_ notification:Notification) { guard !closed else { return };closed = true;onClose?() }
}

private final class InlineEditorPanel:NSPanel {
    override var canBecomeKey:Bool { true }
    override func cancelOperation(_ sender:Any?) { close() }
}
