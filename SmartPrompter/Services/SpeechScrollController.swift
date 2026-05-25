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

    @Published private(set) var estimatedWordsPerMinute: Double = 0
    @Published private(set) var isListening = false
    @Published private(set) var permissionState: PermissionState = .notRequested

    // Audio + recognition
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    // WPM tracking — short rolling window for responsive real-time adjustment
    private var wordTimestamps: [Date] = []
    private let wpmWindowSeconds: TimeInterval = 6   // short = reacts quickly to pace changes
    private var lastTranscription: String = ""
    private var lastWordHeardAt: Date = .distantPast

    // Silence decay — ramps WPM down when you stop speaking
    private var silenceDecayTask: Task<Void, Never>?
    private let silenceThresholdSeconds: TimeInterval = 1.5  // pause before decay starts
    private let decayIntervalMs: UInt64 = 150                // decay tick every 150ms
    private let decayFactor: Double = 0.88                   // 12% reduction per tick

    // MARK: - Public API

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

    func startListening() {
        guard !isListening else { return }
        guard let recognizer = speechRecognizer, recognizer.isAvailable else { return }

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    Task { @MainActor in
                        self.updateWPM(from: result.bestTranscription.formattedString)
                    }
                }

                if error != nil || result?.isFinal == true {
                    Task { @MainActor in
                        self.restartListening()
                    }
                }
            }

            engine.prepare()
            try engine.start()

            isListening = true
            wordTimestamps = []
            lastTranscription = ""
            lastWordHeardAt = .distantPast

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
        estimatedWordsPerMinute = 0
        wordTimestamps = []
        lastTranscription = ""
        lastWordHeardAt = .distantPast
    }

    // MARK: - Private

    /// Called on every partial/final recognition result.
    /// Measures pace over a short rolling window and schedules a silence decay
    /// so the scroll slows naturally when speech stops.
    private func updateWPM(from transcription: String) {
        let newWordCount = countNewWords(current: transcription, previous: lastTranscription)
        lastTranscription = transcription

        guard newWordCount > 0 else { return }

        let now = Date()
        lastWordHeardAt = now

        // New speech heard — cancel any active silence decay
        silenceDecayTask?.cancel()
        silenceDecayTask = nil

        // Stamp the new words
        for _ in 0..<newWordCount {
            wordTimestamps.append(now)
        }

        // Prune anything older than the window
        let cutoff = now.addingTimeInterval(-wpmWindowSeconds)
        wordTimestamps = wordTimestamps.filter { $0 > cutoff }

        // Need at least 2 words and 0.5s of data for a meaningful rate
        guard wordTimestamps.count >= 2, let oldest = wordTimestamps.first else {
            scheduleSilenceDecay()
            return
        }
        let elapsed = now.timeIntervalSince(oldest)
        guard elapsed >= 0.5 else {
            scheduleSilenceDecay()
            return
        }

        let rawWPM = Double(wordTimestamps.count) / elapsed * 60

        // Aggressive EMA (65% new, 35% old) so pace changes register quickly
        estimatedWordsPerMinute = estimatedWordsPerMinute * 0.35 + rawWPM * 0.65

        // Watch for the next silence
        scheduleSilenceDecay()
    }

    /// Waits for the silence threshold, then decays WPM smoothly toward zero.
    /// Cancelled immediately when new speech arrives.
    private func scheduleSilenceDecay() {
        silenceDecayTask?.cancel()
        silenceDecayTask = Task { @MainActor in
            // Wait for the silence threshold before starting decay
            try? await Task.sleep(for: .seconds(silenceThresholdSeconds))
            guard !Task.isCancelled else { return }

            // Ramp WPM down gradually — each tick reduces it by decayFactor
            while !Task.isCancelled && estimatedWordsPerMinute > 1 {
                try? await Task.sleep(nanoseconds: decayIntervalMs * 1_000_000)
                guard !Task.isCancelled else { break }
                estimatedWordsPerMinute *= decayFactor
            }

            if !Task.isCancelled {
                estimatedWordsPerMinute = 0
            }
        }
    }

    private func countNewWords(current: String, previous: String) -> Int {
        let currentCount = current.split(separator: " ").count
        let previousCount = previous.split(separator: " ").count
        return max(0, currentCount - previousCount)
    }

    /// Apple caps recognition sessions at ~1 minute. Restart transparently.
    private func restartListening() {
        guard isListening else { return }
        let preservedWPM = estimatedWordsPerMinute
        let preservedDecayTask = silenceDecayTask
        silenceDecayTask = nil          // prevent stopListening from cancelling it

        stopListening()

        isListening = true
        estimatedWordsPerMinute = preservedWPM
        silenceDecayTask = preservedDecayTask   // re-attach so decay continues across restart

        startListening()
    }
}
