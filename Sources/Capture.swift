import AppKit
import ScreenCaptureKit
import SwiftUI

struct CaptureTarget {
    let display: SCDisplay
    let screen: NSScreen
    let image: CGImage
    let windows: [SCWindow]
}

private struct CaptureConstraintControls: View {
    @State var value:CaptureConstraint
    var changed:(CaptureConstraint)->Void
    var confirm:()->Void
    var maxPixelSize:CGSize
    private var valid:Bool { value.mode != "pixels" || value.pixelWidth > 0 && value.pixelHeight > 0 && CGFloat(value.pixelWidth) <= maxPixelSize.width && CGFloat(value.pixelHeight) <= maxPixelSize.height }
    var body:some View {
        HStack(spacing:10) {
            Picker(L("选区"),selection:$value.mode) {
                Text(L("自由选择")).tag("free");Text(L("全屏")).tag("full");Text(L("固定比例")).tag("ratio");Text(L("指定尺寸")).tag("pixels")
            }.frame(width:210)
            if value.mode == "ratio" {
                Picker(L("比例"),selection:$value.ratio) { ForEach(["1:1","16:9","5:4","7:5","4:3","5:3","3:2"],id:\.self) { Text($0).tag($0) } }.frame(width:140)
                Toggle(L("竖向"),isOn:$value.portrait)
            }
            if value.mode == "pixels" {
                TextField(L("宽"),value:$value.pixelWidth,format:.number.grouping(.never)).frame(width:70)
                Text("×")
                TextField(L("高"),value:$value.pixelHeight,format:.number.grouping(.never)).frame(width:70)
                Text("px")
                Button(L("互换")) { (value.pixelWidth,value.pixelHeight) = (value.pixelHeight,value.pixelWidth) }
            }
            Spacer(minLength:0)
            Button(L("截图"),action:confirm).buttonStyle(.borderedProminent).disabled(!valid)
                .help(LF("最大 %ld × %ld px", Int(maxPixelSize.width), Int(maxPixelSize.height)))
            Text(L("Esc取消")).font(.caption)
        }.padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
        .onChange(of:value) { _,newValue in changed(newValue) }
    }
}

struct CaptureSelection {
    let target: CaptureTarget
    let rect: CGRect // screen-local AppKit points
    var image: NSImage? {
        let scaleX = CGFloat(target.image.width) / target.screen.frame.width
        let scaleY = CGFloat(target.image.height) / target.screen.frame.height
        let pixels = CGRect(x: rect.minX * scaleX,
                            y: (target.screen.frame.height - rect.maxY) * scaleY,
                            width: rect.width * scaleX, height: rect.height * scaleY).integral
        guard let crop = target.image.cropping(to: pixels) else { return nil }
        return NSImage(cgImage: crop, size: rect.size)
    }
    var sourceRect: CGRect {
        CGRect(x: rect.minX, y: target.screen.frame.height - rect.maxY, width: rect.width, height: rect.height)
    }
    var globalFrame:CGRect { rect.offsetBy(dx:target.screen.frame.minX,dy:target.screen.frame.minY) }
}

@MainActor final class CaptureCoordinator {
    private var overlays: [NSPanel] = []
    private var completion: ((CaptureSelection?) -> Void)?
    private(set) var lastSelection: (CGDirectDisplayID, CGRect)?

    func targets() async throws -> [CaptureTarget] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else {
            throw NSError(domain:"ScreenshotKing",code:5,userInfo:[NSLocalizedDescriptionKey:L("无法读取当前窗口顺序")])
        }
        let order = Dictionary(uniqueKeysWithValues:windowInfo.enumerated().map { index,info in ((info[kCGWindowNumber as String] as! NSNumber).uint32Value,index) })
        let orderedWindows = content.windows.sorted { (order[$0.windowID] ?? Int.max) < (order[$1.windowID] ?? Int.max) }
        var result: [CaptureTarget] = []
        for screen in NSScreen.screens {
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let ownWindows = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingWindows: ownWindows)
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            result.append(CaptureTarget(display: display, screen: screen, image: image,
                                        windows: orderedWindows.filter { $0.isOnScreen && $0.windowLayer == 0 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier }))
        }
        return result
    }

    func choose(reuseLast: Bool = false, guides: Bool = false, recognition: String = "window", constraint:CaptureConstraint = CaptureConstraint(), completion: @escaping (Result<CaptureSelection?, Error>) -> Void) {
        guard overlays.isEmpty else { return }
        Task {
            do {
                let targets = try await targets()
                if reuseLast, let last = lastSelection, let target = targets.first(where: { $0.display.displayID == last.0 }) {
                    completion(.success(CaptureSelection(target: target, rect: last.1))); return
                }
                self.completion = { completion(.success($0)) }
                for target in targets {
                    let panel = SelectionPanel(contentRect: target.screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
                    panel.level = .screenSaver
                    panel.isOpaque = true
                    panel.hasShadow = false
                    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                    let view = SelectionView(target: target, guides: guides, recognition: recognition, constraint:constraint) { [weak self] rect in
                        self?.finish(rect.map { CaptureSelection(target: target, rect: $0) })
                    }
                    panel.contentView = view
                    overlays.append(panel)
                    panel.makeKeyAndOrderFront(nil)
                    panel.makeFirstResponder(view)
                }
                NSApp.activate(ignoringOtherApps: true)
            } catch { completion(.failure(error)) }
        }
    }

    private func finish(_ selection: CaptureSelection?) {
        if let selection { lastSelection = (selection.target.display.displayID, selection.rect) }
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        let callback = completion
        completion = nil
        callback?(selection)
    }
}

private final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor private final class SelectionView: NSView {
    let target: CaptureTarget
    let guides: Bool
    let recognition:String
    var constraint:CaptureConstraint
    let done: (CGRect?) -> Void
    var start: CGPoint?
    var mouse = CGPoint.zero
    var selection: CGRect?
    var hover: CGRect?
    var moving = false
    var dragOrigin = CGRect.zero
    var resizeHandle:Int?
    var windowMode = true
    override var acceptsFirstResponder: Bool { true }

    init(target: CaptureTarget, guides: Bool, recognition:String, constraint:CaptureConstraint, done: @escaping (CGRect?) -> Void) {
        self.target = target; self.guides = guides; self.recognition = recognition; self.constraint = constraint;self.done = done
        windowMode = recognition != "off"
        super.init(frame: CGRect(origin: .zero, size: target.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
        let controls = NSHostingView(rootView:CaptureConstraintControls(value:constraint,changed:{ [weak self] value in
            guard let self else { return };self.constraint = value
            if value.mode == "full" { selection = bounds }
            else if let rect = selection { selection = value.rect(from:rect.origin,to:CGPoint(x:rect.maxX,y:rect.maxY),within:bounds,scale:target.screen.backingScaleFactor) }
            needsDisplay = true
        },confirm:{ [weak self] in
            self?.confirmSelection()
        },maxPixelSize:CGSize(width:target.image.width,height:target.image.height)))
        controls.frame = CGRect(x:max(12,(bounds.width-800)/2),y:bounds.height-58,width:min(800,bounds.width-24),height:42)
        controls.autoresizingMask = [.minXMargin,.maxXMargin,.minYMargin]
        addSubview(controls)
        if constraint.mode == "full" { selection = bounds }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        NSImage(cgImage: target.image, size: bounds.size).draw(in: bounds)
        let cutout = selection ?? hover
        let shade = NSBezierPath(rect: bounds)
        if let cutout { shade.append(NSBezierPath(rect: cutout)) }
        shade.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.4).setFill(); shade.fill()
        if guides {
            NSColor.systemCyan.withAlphaComponent(0.7).setStroke()
            let path = NSBezierPath(); path.move(to: CGPoint(x: mouse.x, y: 0)); path.line(to: CGPoint(x: mouse.x, y: bounds.height))
            path.move(to: CGPoint(x: 0, y: mouse.y)); path.line(to: CGPoint(x: bounds.width, y: mouse.y)); path.stroke()
        }
        if let rect = cutout {
            NSColor.systemCyan.setStroke(); let border = NSBezierPath(rect: rect); border.lineWidth = 2; border.stroke()
            if selection != nil {
                NSColor.white.setFill()
                for point in handles(rect) { let knob = NSBezierPath(ovalIn:CGRect(x:point.x-4,y:point.y-4,width:8,height:8));knob.fill();knob.stroke() }
            }
            let label = "\(Int(rect.width * target.screen.backingScaleFactor)) × \(Int(rect.height * target.screen.backingScaleFactor)) px"
            drawLabel(label, at: CGPoint(x: max(12, min(rect.minX, bounds.width - 250)), y: min(bounds.height - 40, rect.maxY + 10)))
            if selection != nil {
                drawLabel(L("回车 截图    拖动 调整    Esc 取消"), at: CGPoint(x: max(12, min(rect.minX, bounds.width - 300)), y: max(12, rect.minY - 36)))
            }
        } else {
            drawLabel(L("拖动框选 · 点击选窗口 · 空格切换窗口/区域 · Esc 取消"), at: CGPoint(x: bounds.midX - 230, y: bounds.height - 80))
        }
        // Frozen pixel magnifier, using the same captured frame as the result.
        if start != nil {
            let side: CGFloat = 100
            let box = CGRect(x: min(bounds.width - side - 10, mouse.x + 24), y: max(12, min(bounds.height - side - 10, mouse.y - side - 24)), width: side, height: side)
            let sx = CGFloat(target.image.width) / bounds.width
            let sy = CGFloat(target.image.height) / bounds.height
            let crop = CGRect(x: mouse.x * sx - 10, y: (bounds.height - mouse.y) * sy - 10, width: 20, height: 20).intersection(CGRect(x: 0,y: 0,width: target.image.width,height: target.image.height))
            if let zoom = target.image.cropping(to: crop) {
                NSGraphicsContext.current?.imageInterpolation = .none
                NSImage(cgImage: zoom, size: box.size).draw(in: box)
                NSColor.white.setStroke(); NSBezierPath(rect: box).stroke()
            }
        }
    }
    func drawLabel(_ label: String, at point: CGPoint) {
        let text = NSAttributedString(string: label, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white])
        let rect = CGRect(origin: point, size: CGSize(width: text.size().width + 20, height: 28))
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect: rect, xRadius: 7, yRadius: 7).fill()
        text.draw(at: CGPoint(x: rect.minX + 10, y: rect.minY + 7))
    }
    override func mouseMoved(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        if selection == nil && windowMode {
            let global = CGPoint(x: mouse.x + target.screen.frame.minX, y: mouse.y + target.screen.frame.minY)
            let height = NSScreen.screens.first?.frame.height ?? target.screen.frame.height
            hover = recognition == "off" ? nil : target.windows.lazy.map { CaptureGeometry.cocoaRect($0.frame, primaryHeight: height) }.first(where: { $0.contains(global) }).map {
                $0.offsetBy(dx: -target.screen.frame.minX, dy: -target.screen.frame.minY).intersection(bounds)
            }
            if recognition == "element", AXIsProcessTrusted() {
                var element:AXUIElement?
                let point = CGPoint(x:global.x,y:height-global.y)
                let owner = target.windows.first { $0.frame.contains(point) }?.owningApplication
                let application = owner.map { AXUIElementCreateApplication($0.processID) }
                if let application, AXUIElementCopyElementAtPosition(application,Float(point.x),Float(point.y),&element) == .success, let element {
                    var origin:CFTypeRef?; var size:CFTypeRef?
                    if AXUIElementCopyAttributeValue(element,kAXPositionAttribute as CFString,&origin) == .success,
                       AXUIElementCopyAttributeValue(element,kAXSizeAttribute as CFString,&size) == .success {
                        var p = CGPoint.zero;var s = CGSize.zero
                        AXValueGetValue(origin as! AXValue,.cgPoint,&p);AXValueGetValue(size as! AXValue,.cgSize,&s)
                        let rect = CaptureGeometry.cocoaRect(CGRect(origin:p,size:s),primaryHeight:height).offsetBy(dx:-target.screen.frame.minX,dy:-target.screen.frame.minY).intersection(bounds)
                        if rect.width > 2 && rect.height > 2 { hover = rect }
                    }
                }
            }
        } else if selection == nil { hover = nil }
        needsDisplay = true
    }
    override func mouseDown(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil); start = mouse
        resizeHandle = selection.flatMap { rect in handles(rect).enumerated().first { hypot($0.element.x-mouse.x,$0.element.y-mouse.y) <= 9 }?.offset }
        moving = resizeHandle == nil && selection?.contains(mouse) == true
        dragOrigin = selection ?? .zero
        if event.clickCount == 2, selection != nil { confirmSelection() }
    }
    override func mouseDragged(with event: NSEvent) {
        mouse = convert(event.locationInWindow, from: nil)
        guard let start else { return }
        if let handle = resizeHandle {
            var left = dragOrigin.minX,right = dragOrigin.maxX,bottom = dragOrigin.minY,top = dragOrigin.maxY
            if [0,3,5].contains(handle) { left = max(0,min(mouse.x,right-2)) }
            if [2,4,7].contains(handle) { right = min(bounds.width,max(mouse.x,left+2)) }
            if [0,1,2].contains(handle) { bottom = max(0,min(mouse.y,top-2)) }
            if [5,6,7].contains(handle) { top = min(bounds.height,max(mouse.y,bottom+2)) }
            selection = constraint.rect(from:CGPoint(x:left,y:bottom),to:CGPoint(x:right,y:top),within:bounds,scale:target.screen.backingScaleFactor)
        } else if moving {
            var rect = dragOrigin.offsetBy(dx: mouse.x - start.x, dy: mouse.y - start.y)
            rect.origin.x = max(0, min(bounds.width - rect.width, rect.origin.x))
            rect.origin.y = max(0, min(bounds.height - rect.height, rect.origin.y))
            selection = rect
        } else { selection = constraint.rect(from:start,to:mouse,within:bounds,scale:target.screen.backingScaleFactor) }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if selection == nil, let hover { selection = constraint.rect(from:hover.origin,to:CGPoint(x:hover.maxX,y:hover.maxY),within:bounds,scale:target.screen.backingScaleFactor) }
        start = nil
        resizeHandle = nil
        needsDisplay = true
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: done(nil)
        case 36, 76:
            confirmSelection()
        case 49: windowMode.toggle();selection = nil; hover = nil; needsDisplay = true
        case 7:
            if constraint.mode == "pixels" { (constraint.pixelWidth,constraint.pixelHeight) = (constraint.pixelHeight,constraint.pixelWidth) }
            else { constraint.portrait.toggle() }
            if let rect = selection { selection = constraint.rect(from:rect.origin,to:CGPoint(x:rect.maxX,y:rect.maxY),within:bounds,scale:target.screen.backingScaleFactor) };needsDisplay = true
        case 123, 124, 125, 126:
            if var rect = selection {
                let amount: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let dx: CGFloat = event.keyCode == 123 ? -amount : event.keyCode == 124 ? amount : 0
                let dy: CGFloat = event.keyCode == 125 ? -amount : event.keyCode == 126 ? amount : 0
                if event.modifierFlags.contains(.option) { rect.size.width += dx; rect.size.height += dy }
                else { rect.origin.x += dx; rect.origin.y += dy }
                selection = rect.intersection(bounds); needsDisplay = true
            }
        default: super.keyDown(with: event)
        }
    }
    func confirmSelection() {
        if constraint.mode == "pixels",constraint.pixelWidth <= 0 || constraint.pixelHeight <= 0 || constraint.pixelWidth > target.image.width || constraint.pixelHeight > target.image.height { NSSound.beep();return }
        guard let selection,selection.width >= 2,selection.height >= 2 else { NSSound.beep();return }
        done(selection)
    }
    func handles(_ rect:CGRect)->[CGPoint] {
        [CGPoint(x:rect.minX,y:rect.minY),CGPoint(x:rect.midX,y:rect.minY),CGPoint(x:rect.maxX,y:rect.minY),CGPoint(x:rect.minX,y:rect.midY),CGPoint(x:rect.maxX,y:rect.midY),CGPoint(x:rect.minX,y:rect.maxY),CGPoint(x:rect.midX,y:rect.maxY),CGPoint(x:rect.maxX,y:rect.maxY)]
    }
}
