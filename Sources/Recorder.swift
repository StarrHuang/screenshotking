import AppKit
import ScreenCaptureKit
import AVFoundation
import SwiftUI

@available(macOS 15.0, *)
@MainActor final class ScreenRecorder: NSObject, ObservableObject, SCRecordingOutputDelegate, SCStreamDelegate {
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var status = ""
    var changed: (() -> Void)?
    private var stream: SCStream?
    private var recording: SCRecordingOutput?
    private var outputURL: URL?
    private var cameraSession: AVCaptureSession?
    private var cameraPanel: NSPanel?
    private var controls: NSPanel?
    private var stopping = false

    func start(selection: CaptureSelection, url: URL, systemAudio: Bool, microphone: Bool, camera: Bool, silent:Bool = false) async throws {
        guard !isBusy else { throw permissionError("录屏已经启动或正在保存") }
        isBusy = true
        do {
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) { throw permissionError("麦克风权限未授权") }
        if camera { try await showCamera(selection: selection) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let cameras = content.windows.filter { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && $0.title == "ScreenshotKing Camera" }
        // Exclude the application, including control windows created after the filter.
        let filter = SCContentFilter(display: selection.target.display, excludingApplications: ownApps, exceptingWindows: cameras)
        let config = SCStreamConfiguration()
        config.sourceRect = selection.sourceRect
        // H.264 dimensions must be even. Keep the entire selected region, scaling by at most one pixel.
        let scale = selection.target.screen.backingScaleFactor
        config.width = max(2, Int(selection.rect.width * scale) / 2 * 2)
        config.height = max(2, Int(selection.rect.height * scale) / 2 * 2)
        config.minimumFrameInterval = CMTime(value: 1,timescale: 30)
        config.showsCursor = true
        config.capturesAudio = systemAudio
        config.excludesCurrentProcessAudio = true
        config.captureMicrophone = microphone
        let outputConfig = SCRecordingOutputConfiguration(); outputConfig.outputURL = url
        outputConfig.videoCodecType = .h264; outputConfig.outputFileType = .mp4
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
            try stream.addRecordingOutput(output)
            self.stream = stream; self.recording = output; self.outputURL = url
            stopping = false; status = "正在启动录屏…"
            try await stream.startCapture()
            if !silent { showControls() }
        } catch {
            cleanup()
            throw error
        }
    }
    func stop() {
        guard !stopping, let stream else { return }
        stopping = true; status = "正在写入录屏…"; changed?()
        Task {
            do { try await stream.stopCapture() }
            catch { fail(error) }
        }
    }
    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.isRecording = true; self.status = "录屏中"; self.changed?() }
    }
    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.fail(error) }
    }
    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in
            self.isRecording = false; self.status = "录屏已保存"
            self.cleanup(); self.changed?()
            if let url = self.outputURL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.fail(error) }
    }
    private func fail(_ error: Error) {
        isRecording = false; status = "录屏失败：\(error.localizedDescription)"; cleanup(); changed?()
        NSAlert(error: error).runModal()
    }
    private func cleanup() {
        cameraSession?.stopRunning(); cameraSession = nil; cameraPanel?.close(); cameraPanel = nil
        controls?.close(); controls = nil; stream = nil; recording = nil; stopping = false; isBusy = false
    }
    private func permissionError(_ message: String) -> NSError { NSError(domain: "ScreenshotKing", code: 2,userInfo: [NSLocalizedDescriptionKey:message]) }
    private func showControls() {
        let panel = NSPanel(contentRect: CGRect(x: 30,y: 40,width: 260,height: 65),styleMask:[.titled,.utilityWindow],backing:.buffered,defer:false)
        panel.title = "ScreenshotKing · 录屏"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: RecordingControls(recorder: self))
        controls = panel; panel.orderFrontRegardless()
    }
    private func showCamera(selection: CaptureSelection) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw permissionError("摄像头权限未授权") }
        guard let device = AVCaptureDevice.default(for: .video) else { throw permissionError("没有可用的摄像头") }
        let session = AVCaptureSession(); session.sessionPreset = .medium
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw permissionError("无法添加摄像头输入") }
        session.addInput(input)
        let size = min(200,selection.rect.width * 0.3,selection.rect.height * 0.3)
        let rect = CGRect(x: selection.target.screen.frame.minX + selection.rect.minX + 12,y: selection.target.screen.frame.minY + selection.rect.minY + 12,width:size,height:size)
        let panel = NSPanel(contentRect:rect,styleMask:[.borderless],backing:.buffered,defer:false)
        panel.title = "ScreenshotKing Camera"; panel.level = .floating; panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true; panel.isOpaque = false; panel.backgroundColor = .clear
        let view = NSView(frame:CGRect(origin:.zero,size:rect.size)); view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session:session); layer.videoGravity = .resizeAspectFill; layer.frame = view.bounds
        layer.cornerRadius = size/2; layer.masksToBounds = true; view.layer = layer
        panel.contentView = view; cameraSession = session; cameraPanel = panel; panel.orderFrontRegardless()
        // AVCaptureSession's blocking start is kept off the UI thread.
        await Task.detached { session.startRunning() }.value
    }
}

@available(macOS 15.0, *)
private struct RecordingControls: View {
    @ObservedObject var recorder: ScreenRecorder
    var body: some View {
        HStack(spacing:12) {
            Circle().fill(.red).frame(width:9,height:9)
            Text(recorder.status).font(.callout)
            Spacer()
            Button("停止并保存") { recorder.stop() }.disabled(!recorder.isRecording)
        }.padding(14).frame(width:300)
    }
}
