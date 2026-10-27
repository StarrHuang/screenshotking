import AppKit

private final class FlippedView:NSView { override var isFlipped:Bool { true } }

@main @MainActor final class QAHost:NSObject,NSApplicationDelegate {
    var window:NSWindow!
    var sound:NSSound?
    var pasteTarget:NSTextField!
    static func main() {
        let app = NSApplication.shared;let owner = QAHost();app.delegate = owner;app.setActivationPolicy(.regular);app.run();withExtendedLifetime(owner) {}
    }
    func applicationDidFinishLaunching(_ notification:Notification) {
        let menu = NSMenu();let appItem = NSMenuItem();let sub = NSMenu();sub.addItem(withTitle:"Quit",action:#selector(NSApplication.terminate(_:)),keyEquivalent:"q");appItem.submenu = sub;menu.addItem(appItem)
        let editItem = NSMenuItem();let edit = NSMenu(title:"Edit");for (title,selector,key) in [("Copy",#selector(NSText.copy(_:)),"c"),("Paste",#selector(NSText.paste(_:)),"v"),("Select All",#selector(NSText.selectAll(_:)),"a")] { edit.addItem(withTitle:title,action:selector,keyEquivalent:key) };editItem.submenu = edit;menu.addItem(editItem);NSApp.mainMenu = menu
        window = NSWindow(contentRect:CGRect(x:100,y:90,width:640,height:740),styleMask:[.titled,.closable,.resizable],backing:.buffered,defer:false);window.title = "ScreenshotKing QA · synthetic content"
        let root = FlippedView(frame:CGRect(x:0,y:0,width:640,height:740));window.contentView = root
        let copy = NSButton(title:"复制 QA 测试文本",target:self,action:#selector(copyText));copy.frame = CGRect(x:20,y:12,width:180,height:30);root.addSubview(copy)
        let tone = NSButton(title:"播放 8 秒测试音",target:self,action:#selector(playTone));tone.frame = CGRect(x:220,y:12,width:180,height:30);root.addSubview(tone)
        let input = NSTextField(frame:CGRect(x:20,y:52,width:590,height:30));input.placeholderString = "Paste target (QA only)";input.identifier = NSUserInterfaceItemIdentifier("qa-paste-target");root.addSubview(input);pasteTarget = input
        let scroll = NSScrollView(frame:CGRect(x:20,y:105,width:600,height:610));scroll.hasVerticalScroller = true;scroll.borderType = .bezelBorder
        let document = FlippedView(frame:CGRect(x:0,y:0,width:580,height:2800));document.wantsLayer = true;document.layer?.backgroundColor = NSColor.white.cgColor
        for i in 0..<28 {
            let row = FlippedView(frame:CGRect(x:0,y:i*100,width:580,height:100));row.wantsLayer = true
            row.layer?.backgroundColor = NSColor(calibratedRed:CGFloat(i)/38+0.2,green:0.82-CGFloat(i)/90,blue:0.88-CGFloat(i)/80,alpha:1).cgColor
            let label = NSTextField(labelWithString:String(format:"ROW %02d · ScreenshotKing QA",i+1));label.font = .boldSystemFont(ofSize:21);label.frame = CGRect(x:22,y:20,width:530,height:30);row.addSubview(label)
            let detail = NSTextField(labelWithString:"Synthetic pixels · scroll / capture / OCR verification");detail.frame = CGRect(x:22,y:57,width:530,height:25);row.addSubview(detail);document.addSubview(row)
        }
        scroll.documentView = document;root.addSubview(scroll);window.center();window.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
        NSEvent.addLocalMonitorForEvents(matching:.scrollWheel) { event in
            let line = "window=\(event.windowNumber) location=\(event.locationInWindow) delta=\(event.scrollingDeltaX),\(event.scrollingDeltaY) precise=\(event.hasPreciseScrollingDeltas)\n"
            let url = URL(fileURLWithPath:Bundle.main.bundlePath).deletingLastPathComponent().appendingPathComponent("qa-scroll-events.log")
            if let handle = try? FileHandle(forWritingTo:url) { handle.seekToEndOfFile();handle.write(Data(line.utf8));try? handle.close() }
            else { try? line.write(to:url,atomically:true,encoding:.utf8) }
            return event
        }
    }
    @objc func copyText() { NSRunningApplication.current.activate(options:[.activateAllWindows,.activateIgnoringOtherApps]);window.makeKeyAndOrderFront(nil);window.makeFirstResponder(pasteTarget);NSPasteboard.general.clearContents();NSPasteboard.general.setString("ScreenshotKing clipboard QA 2026",forType:.string) }
    @objc func playTone() { sound = NSSound(contentsOf:URL(fileURLWithPath:Bundle.main.bundlePath).appendingPathComponent("Contents/Resources/test-tone.wav"),byReference:false);sound?.play() }
}
