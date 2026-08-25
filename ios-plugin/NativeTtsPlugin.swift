import Foundation
import Capacitor
import AVFoundation

/**
 * NativeTtsPlugin
 *
 * Drop-in replacement for the browser's `speechSynthesis` API, backed by
 * AVSpeechSynthesizer. Advantages over the web TTS Citolex uses today:
 *   - Works fully offline (no network round-trip for the voice)
 *   - Can keep speaking with the screen locked / app backgrounded, as long
 *     as the "Audio, AirPlay, and Picture in Picture" background mode is
 *     enabled on the app target (see SETUP.md)
 *   - Access to every voice installed on the device, including the higher
 *     quality "Enhanced"/"Premium" voices users may have downloaded in
 *     Settings > Accessibility > Spoken Content > Voices
 *
 * Install this file in your Xcode project under App/ (drag it into the
 * "App" target in Xcode after `npx cap add ios`). Capacitor's build step
 * auto-discovers @objc(NativeTts)-annotated plugin classes, no manual
 * registration needed beyond that.
 */
@objc(NativeTts)
public class NativeTtsPlugin: CAPPlugin, CAPBridgedPlugin, AVSpeechSynthesizerDelegate {

    public let identifier = "NativeTtsPlugin"
    public let jsName = "NativeTts"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "listVoices", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "speak", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "resume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise)
    ]

    private let synthesizer = AVSpeechSynthesizer()
    private var currentCall: CAPPluginCall?
    private var currentUtterance: AVSpeechUtterance?

    public override func load() {
        synthesizer.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    // Re-asserts the .playback audio-session category right before every
    // utterance, instead of relying on the one-time setup in load(). That
    // one-time call is what makes TTS audible even with the phone's silent
    // switch flipped — if it silently failed (or got superseded by anything
    // else touching the shared AVAudioSession between load() and the first
    // speak(), e.g. another app holding the session at launch), every
    // utterance since would have gone out silently on whatever category the
    // session fell back to, with no error ever surfaced. Called from speak()
    // below; throws instead of swallowing failures so the JS side's promise
    // actually rejects and the UI doesn't claim "playing" over dead air.
    private func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
    }

    @objc func listVoices(_ call: CAPPluginCall) {
        let voices = AVSpeechSynthesisVoice.speechVoices().map { v -> [String: String] in
            return ["identifier": v.identifier, "name": v.name, "language": v.language]
        }
        call.resolve(["voices": voices])
    }

    @objc func speak(_ call: CAPPluginCall) {
        guard let text = call.getString("text"), !text.isEmpty else {
            call.reject("text is required")
            return
        }
        do {
            try activateAudioSession()
        } catch {
            call.reject("could not activate audio session: \(error.localizedDescription)")
            return
        }

        // AVSpeechSynthesizer does not interrupt an in-progress utterance
        // when speak() is called again — it queues the new one to play
        // *after* the current one finishes. Without this, changing WPM or
        // voice mid-playback stacked utterances back to back while
        // currentCall (below) only ever tracked the newest one, leaving the
        // JS side's play/pause state completely out of sync with what was
        // actually still speaking. stopSpeaking triggers the didCancel
        // delegate below, which resolves and clears out whatever the
        // previous currentCall was before we replace it further down.
        if synthesizer.isSpeaking || synthesizer.isPaused {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Citolex's web rate slider is 0.5x-2.0x tied to WPM; AVSpeechUtterance
        // rate is 0.0-1.0 with 0.5 being the natural/default speaking rate, so
        // we scale around that midpoint to keep the same *feel* as the browser
        // version rather than mapping the numbers 1:1.
        let rateMultiplier = call.getDouble("rate") ?? 1.0
        utterance.rate = Float(min(1.0, max(0.05, 0.5 * rateMultiplier)))

        if let voiceId = call.getString("voiceId"),
           let voice = AVSpeechSynthesisVoice(identifier: voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        }

        currentUtterance = utterance
        currentCall = call
        call.keepAlive = true // resolves later via delegate, on finish/stop

        synthesizer.speak(utterance)
    }

    @objc func pause(_ call: CAPPluginCall) {
        // AVSpeechSynthesizer.pauseSpeaking(at:) is documented but genuinely
        // flaky right around utterance/chunk boundaries — it can return
        // having silently done nothing, leaving audio still playing while
        // the JS side (which doesn't wait for any confirmation here) has
        // already flipped the icon to "paused". stopSpeaking(at:) has no
        // such flakiness — it always actually stops. The JS "play" path
        // never relies on true resume anyway (it always restarts a fresh
        // utterance from the current word), so a hard stop here is exactly
        // as resumable as a real pause would have been, just reliable.
        synthesizer.stopSpeaking(at: .immediate)
        call.resolve()
    }

    @objc func resume(_ call: CAPPluginCall) {
        synthesizer.continueSpeaking()
        call.resolve()
    }

    @objc func stop(_ call: CAPPluginCall) {
        synthesizer.stopSpeaking(at: .immediate)
        call.resolve()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        // Lets the JS side only flip the play/pause icon to "playing" once
        // speech has actually, confirmedly started — see the matching JS
        // change in startSpeakingNative()/playBtn's click handler.
        notifyListeners("start", data: [:])
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        notifyListeners("boundary", data: ["charIndex": characterRange.location])
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        notifyListeners("finish", data: [:])
        currentCall?.resolve()
        currentCall = nil
    }

    public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        currentCall?.resolve()
        currentCall = nil
    }
}
