import AVFoundation
import Combine
import Foundation
import Speech

/// Drives the smart voice scroll feature.
///
/// Architecture
/// ────────────
/// Two independent signals feed `scrollSpeedMultiplier`:
///
/// 1. **Audio energy envelope** (fires ~43×/sec, <50 ms latency)
///    An envelope follower on raw microphone RMS.  Fast attack so scrolling
///    starts the instant you speak; medium release (~350 ms) so the scroll
///    bridges natural inter-word gaps without stuttering.
///    This is the primary on/off driver.
///
/// 2. **Speech recognition pace** (fires every 0.5–1.5 s)
///    A rolling WPM window derived from the recogniser's partial results.
///    Used only to gently modulate the target multiplier (slow speaker → ~0.7×,
///    fast speaker → ~1.5×).  The recogniser's latency is fine here because
///    pace changes happen over several seconds, not milliseconds.
///    The recogniser also drives the word-highlight cursor (`currentWordIndex`).
@MainActor
final class SpeechScrollController: ObservableObject {

    enum PermissionState: String {
        case notRequested = "Not Requested"
        case denied       = "Denied"
        case granted      = "Ready"
    }

    @Published private(set) var isListening           = false
    @Published private(set) var permissionState: PermissionState = .notRequested

    /// 0 = silent/stopped, ~1.0 = speaking at baseline pace, up to ~1.6 for fast speech.
    /// Used directly as the scroll speed multiplier in TeleprompterView.
    @Published private(set) var scrollSpeedMultiplier: Double = 0

    /// Index of the NEXT word to be spoken.  TeleprompterView uses this to highlight
    /// the current word so the reader always knows where they are.
    @Published private(set) var currentWordIndex: Int = 0

    // ── Audio + recognition ──────────────────────────────────────────────────
    private var audioEngine:        AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask:    SFSpeechRecognitionTask?
    private let speechRecognizer  = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // ── Script word matching (highlight cursor only) ─────────────────────────
    private var scriptWordsCleaned: [String] = []
    private var lastTranscription:  String   = ""

    // ── Audio energy envelope ────────────────────────────────────────────────
    // Smoothed RMS amplitude of the microphone signal.
    // attackCoeff: applied when new sample > envelope  → fast rise  (~46 ms to 80%)
    // releaseCoeff: applied when new sample < envelope → medium fall (~350 ms to 10%)
    // This bridges inter-word gaps (~100–200 ms) but stops scrolling on deliberate
    // pauses (~400 ms+).
    private var voiceEnvelope:   Double = 0
    private let attackCoeff:     Double = 0.55
    private let releaseCoeff:    Double = 0.88
    private let noiseFloor:      Double = 0.006   // below this → silence

    // ── Pace multiplier (from speech recognition) ────────────────────────────
    // Slow-moving target: 0.5 for slow speakers, 1.0 at baseline, up to 1.6 fast.
    private var paceMultiplier: Double = 1.0
    private var wordTimestamps: [Date] = []
    private let wpmWindow:      TimeInterval = 5
    private var lastBatchTime:  Date = .distantPast
    private let baselineWPM:    Double = 150

    // MARK: - Script setup

    func setScript(_ text: String) {
        scriptWordsCleaned = tokenise(text)
        currentWordIndex   = 0
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { permissionState = .denied; return false }

        let micGranted = await AVAudioApplication.requestRecordPermission()
        if micGranted { permissionState = .granted; return true }
        else          { permissionState = .denied;  return false }
    }

    // MARK: - Listening lifecycle

    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine  = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            let inputNode = engine.inputNode
            let format    = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                guard let self else { return }
                // Feed the recogniser (word cursor / pace)
                self.recognitionRequest?.append(buf)
                // Compute RMS cheaply on the audio thread, dispatch result to main
                let rms = Self.computeRMS(buf)
                Task { @MainActor [weak self] in
                    self?.updateEnvelope(rms: Double(rms))
                }
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.processTranscription(result.bestTranscription.formattedString)
                    }
                }
                if error != nil || result?.isFinal == true {
                    Task { @MainActor in self.restartListening() }
                }
            }

            engine.prepare()
            try engine.start()

            isListening           = true
            scrollSpeedMultiplier = 0
            voiceEnvelope         = 0
            paceMultiplier        = 1.0
            lastTranscription     = ""
            lastBatchTime         = .distantPast
            wordTimestamps        = []

        } catch {
            isListening = false
        }
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine        = nil
        recognitionRequest = nil
        recognitionTask    = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isListening           = false
        scrollSpeedMultiplier = 0
        voiceEnvelope         = 0
        lastTranscription     = ""
        wordTimestamps        = []
    }

    // MARK: - Audio energy → scroll multiplier

    /// Called ~43×/second on the main actor.
    /// Runs an envelope follower and converts it to `scrollSpeedMultiplier`.
    private func updateEnvelope(rms: Double) {
        // Envelope follower: fast attack, medium release
        if rms > voiceEnvelope {
            voiceEnvelope = attackCoeff * rms + (1 - attackCoeff) * voiceEnvelope
        } else {
            voiceEnvelope = releaseCoeff * voiceEnvelope
        }

        if voiceEnvelope < noiseFloor {
            // Silence: ramp multiplier to 0 quickly (~140 ms to fully stop)
            scrollSpeedMultiplier = max(0, scrollSpeedMultiplier - 0.18)
        } else {
            // Voice active: ease toward paceMultiplier
            // 0.35 weight on target → reaches 82% in ~4 ticks (~93 ms) — feels immediate
            let target = paceMultiplier
            scrollSpeedMultiplier = min(2.0, 0.35 * target + 0.65 * scrollSpeedMultiplier)
        }
    }

    /// Root-mean-square amplitude of a mono PCM buffer. Fast, runs on the audio thread.
    private static func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        return sqrt(sum / Float(count))
    }

    // MARK: - Speech recognition → word cursor + pace

    private func processTranscription(_ transcription: String) {
        let newWords = extractNewWords(from: transcription, previous: lastTranscription)
        lastTranscription = transcription
        guard !newWords.isEmpty else { return }

        let now           = Date()
        let timeSinceLast = now.timeIntervalSince(lastBatchTime)
        lastBatchTime     = now

        // Advance word-highlight cursor
        advanceCursor(newWords: newWords)

        // Update rolling WPM → paceMultiplier
        for _ in newWords { wordTimestamps.append(now) }
        let cutoff = now.addingTimeInterval(-wpmWindow)
        wordTimestamps = wordTimestamps.filter { $0 > cutoff }

        if wordTimestamps.count >= 3, let oldest = wordTimestamps.first {
            let elapsed = now.timeIntervalSince(oldest)
            if elapsed >= 0.5, timeSinceLast > 0.05, timeSinceLast < 8.0 {
                let windowWPM = Double(wordTimestamps.count) / elapsed * 60
                let raw       = windowWPM / baselineWPM
                // Gentle smoothing — pace is a slow-moving signal, that's intentional
                paceMultiplier = min(1.6, max(0.5, 0.6 * raw + 0.4 * paceMultiplier))
            }
        }
    }

    /// Greedy forward match: scan up to 15 words ahead for each newly spoken word.
    private func advanceCursor(newWords: [String]) {
        for word in newWords {
            let limit = min(scriptWordsCleaned.count, currentWordIndex + 15)
            for i in currentWordIndex..<limit {
                let s = scriptWordsCleaned[i]
                if s == word || s.hasPrefix(word) || word.hasPrefix(s) {
                    currentWordIndex = i + 1
                    break
                }
            }
        }
    }

    // MARK: - Helpers

    private func extractNewWords(from current: String, previous: String) -> [String] {
        let curr      = current.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let prevCount = previous.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        guard curr.count > prevCount else { return [] }
        return Array(curr.suffix(curr.count - prevCount)).map { normalise($0) }
    }

    private func tokenise(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map    { normalise($0) }
    }

    private func normalise(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Transparent restart to work around Apple's ~1-minute session cap.
    /// Preserves envelope and pace so there's no glitch during the handover.
    private func restartListening() {
        guard isListening else { return }
        let savedMultiplier = scrollSpeedMultiplier
        let savedPace       = paceMultiplier
        let savedEnvelope   = voiceEnvelope

        stopListening()

        isListening           = true
        scrollSpeedMultiplier = savedMultiplier
        paceMultiplier        = savedPace
        voiceEnvelope         = savedEnvelope

        startListening()
    }
}
