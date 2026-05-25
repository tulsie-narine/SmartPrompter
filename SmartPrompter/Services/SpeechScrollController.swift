import AVFoundation
import Combine
import Foundation
import Speech

@MainActor
final class SpeechScrollController: ObservableObject {
    enum PermissionState: String {
        case notRequested = "Not Requested"
        case denied = "Denied"
        case granted = "Ready"
    }

    @Published private(set) var isListening = false
    @Published private(set) var permissionState: PermissionState = .notRequested

    /// 0 = stopped/silent, 1 = speaking at baseline pace, up to 2 = speaking fast.
    /// Used directly as the scroll speed multiplier in TeleprompterView.
    @Published private(set) var scrollSpeedMultiplier: Double = 0

    /// Index of the NEXT word to be spoken in the script word list.
    /// TeleprompterView highlights this word so the reader always knows where they are.
    @Published private(set) var currentWordIndex: Int = 0

    // Audio + recognition
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // Script word matching
    private var scriptWordsCleaned: [String] = []   // normalised tokens for matching
    private var lastTranscription: String = ""

    // Pace tracking — short rolling window gives fast response to speed changes
    private var wordTimestamps: [Date] = []
    private let wpmWindow: TimeInterval = 4          // 4-second window = fast to update
    private var lastBatchTime: Date = .distantPast

    // Silence decay — makes scroll slow/stop when you pause between words
    private var silenceDecayTask: Task<Void, Never>?
    private let silenceThreshold: TimeInterval = 0.7  // 0.7s pause triggers decay
    private let decayInterval: UInt64 = 100            // tick every 100ms
    private let decayFactor: Double = 0.75             // 25% drop per tick → stops in ~1.2s

    // Baseline speaking pace in WPM
    private let baselineWPM: Double = 165

    // MARK: - Script setup

    /// Call once when the script is loaded. Tokenises the text so incoming speech
    /// can be matched word-by-word to advance the highlight cursor.
    func setScript(_ text: String) {
        scriptWordsCleaned = tokenise(text)
        currentWordIndex = 0
    }

    // MARK: - Permissions

    func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            permissionState = .denied
            return false
        }

        let micGranted = await AVAudioApplication.requestRecordPermission()

        if micGranted {
            permissionState = .granted
            return true
        } else {
            permissionState = .denied
            return false
        }
    }

    // MARK: - Listening lifecycle

    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buf, _ in
                self?.recognitionRequest?.append(buf)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                if let result {
                    Task { @MainActor in
                        self.process(transcription: result.bestTranscription.formattedString)
                    }
                }
                if error != nil || result?.isFinal == true {
                    Task { @MainActor in self.restartListening() }
                }
            }

            engine.prepare()
            try engine.start()

            isListening = true
            scrollSpeedMultiplier = 0
            lastTranscription = ""
            lastBatchTime = .distantPast
            wordTimestamps = []

        } catch {
            isListening = false
        }
    }

    func stopListening() {
        silenceDecayTask?.cancel()
        silenceDecayTask = nil

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isListening = false
        scrollSpeedMultiplier = 0
        lastTranscription = ""
        wordTimestamps = []
    }

    // MARK: - Core processing

    private func process(transcription: String) {
        let newWords = extractNewWords(from: transcription, previous: lastTranscription)
        lastTranscription = transcription
        guard !newWords.isEmpty else { return }

        let now = Date()
        let timeSinceLast = now.timeIntervalSince(lastBatchTime)
        lastBatchTime = now

        // Speech is happening — cancel any active silence decay immediately
        silenceDecayTask?.cancel()
        silenceDecayTask = nil

        // --- Advance word cursor for highlighting ---
        advanceCursor(newWords: newWords)

        // --- Pace measurement ---
        // Stamp new words and prune old timestamps
        for _ in newWords { wordTimestamps.append(now) }
        let cutoff = now.addingTimeInterval(-wpmWindow)
        wordTimestamps = wordTimestamps.filter { $0 > cutoff }

        // Compute pace from rolling window
        if wordTimestamps.count >= 2, let oldest = wordTimestamps.first {
            let elapsed = now.timeIntervalSince(oldest)
            if elapsed >= 0.3 {
                let windowWPM = Double(wordTimestamps.count) / elapsed * 60
                let rawMultiplier = windowWPM / baselineWPM

                // 80% new / 20% old — reacts to pace changes within 1–2 recognition batches
                if timeSinceLast > 0.05 && timeSinceLast < 6.0 {
                    scrollSpeedMultiplier = min(2.0, scrollSpeedMultiplier * 0.2 + rawMultiplier * 0.8)
                } else {
                    // First batch or restart — snap to measured pace
                    scrollSpeedMultiplier = min(2.0, max(0.1, rawMultiplier))
                }
            }
        } else {
            // Not enough data yet — assume baseline pace
            if scrollSpeedMultiplier == 0 { scrollSpeedMultiplier = 1.0 }
        }

        // Watch for the next pause
        scheduleSilenceDecay()
    }

    /// Greedy forward match: for each newly spoken word, scan ahead in the script
    /// and advance the cursor to the first match found.
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

    /// Waits for the silence threshold then smoothly ramps scroll speed to zero.
    /// Any new speech cancels it instantly.
    private func scheduleSilenceDecay() {
        silenceDecayTask?.cancel()
        silenceDecayTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(silenceThreshold))
            guard !Task.isCancelled else { return }

            while !Task.isCancelled && scrollSpeedMultiplier > 0.02 {
                try? await Task.sleep(nanoseconds: decayInterval * 1_000_000)
                guard !Task.isCancelled else { break }
                scrollSpeedMultiplier *= decayFactor
            }
            if !Task.isCancelled { scrollSpeedMultiplier = 0 }
        }
    }

    // MARK: - Helpers

    private func extractNewWords(from current: String, previous: String) -> [String] {
        let curr = current.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        let prevCount = previous.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        guard curr.count > prevCount else { return [] }
        return Array(curr.suffix(curr.count - prevCount)).map { normalise($0) }
    }

    private func tokenise(_ text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { normalise($0) }
    }

    private func normalise(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    /// Transparent restart to work around Apple's ~1-minute session cap.
    private func restartListening() {
        guard isListening else { return }
        let savedMultiplier = scrollSpeedMultiplier
        let savedDecay = silenceDecayTask
        silenceDecayTask = nil          // prevent stopListening from cancelling it

        stopListening()

        isListening = true
        scrollSpeedMultiplier = savedMultiplier
        silenceDecayTask = savedDecay

        startListening()
    }
}
