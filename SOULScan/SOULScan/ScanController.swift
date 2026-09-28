import SwiftUI
import AVFoundation

final class ScanController: ObservableObject {
    @Published var snapshot=ScanSnapshot()
    @Published var error: String?
    @Published var saved: ScanRecord?
    @Published var countdown: Int?
    @Published var finishing=false
    private let camera=DepthCamera()
    private let speaker=AVSpeechSynthesizer()
    private var countdownTask: Task<Void,Never>?
    private var lastGuidance=Date.distantPast
    private var active=false
    init(root: URL, side: FootSide, activity: String, reference: String) {
        camera.prepare(root:root,side:side,activity:activity,reference:reference)
        camera.onUpdate={ [weak self] state in
            guard let self else { return }; self.snapshot=state
            if state.isRecording && Date().timeIntervalSince(self.lastGuidance)>8 {
                self.lastGuidance=Date(); self.say(state.status)
            }
        }
        camera.onError={ [weak self] text in self?.error=text; self?.finishing=false }
        camera.onSaved={ [weak self] record in self?.saved=record; self?.finishing=false; self?.say("Scan saved. Review the surface before exporting.") }
        camera.onRecordingChanged={ [weak self] value in self?.snapshot.isRecording=value; if value { self?.say("Scanning. Keep the foot still. Move the phone slowly."); UIImpactFeedbackGenerator(style:.medium).impactOccurred() } }
    }
    func startCamera() { active=true; camera.start() }
    func suspend() { active=false; countdownTask?.cancel(); countdown=nil; camera.pause(); camera.stop(); speaker.stopSpeaking(at:.immediate) }
    func begin() {
        guard snapshot.canCapture, !snapshot.isRecording, countdown==nil else { return }
        countdownTask=Task { @MainActor [weak self] in
            guard let self else { return }
            for n in (1...3).reversed() { guard !Task.isCancelled,self.active else { self.countdown=nil; return }; self.countdown=n; self.say(String(n)); try? await Task.sleep(nanoseconds:1_000_000_000) }
            guard !Task.isCancelled,self.active else { self.countdown=nil; return }; self.countdown=nil; self.camera.begin()
        }
    }
    func pause() { countdownTask?.cancel();countdown=nil;camera.pause();say("Paused.") }
    func finish() { countdownTask?.cancel();countdown=nil;finishing=true;camera.finish() }
    func discard() { suspend();camera.discard() }
    private func say(_ text: String) { guard !speaker.isSpeaking else { return }; let utterance=AVSpeechUtterance(string:text);utterance.voice=AVSpeechSynthesisVoice(language:"en-CA");utterance.rate=0.48;speaker.speak(utterance) }
}
