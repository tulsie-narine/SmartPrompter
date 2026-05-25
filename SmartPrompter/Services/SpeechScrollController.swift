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

    // WPM tracking — sliding window over the last N seconds
    private var wordTimestamps: [Date] = []
    private let wpmWindowSeconds: TimeInterval = 20
    private var lastTranscription: String = ""

    // MARK: - Public API

    func requestPermissions() async -> Bool {
        // 1. Speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard speechStatus == .authorized else {
            permissionState = .denied
            return false
        }

        // 2. Microphone permission (iOS 17+ API)
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
            // Configure audio session for recording
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            audioEngine = engine

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.taskHint = .dictation
            recognitionRequest = request

            // Tap the microphone input and feed buffers into the recognizer
            let inputNode = engine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.recognitionRequest?.append(buffer)
            }

            // Handle incoming transcription results
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    Task { @MainActor in
                        self.updateWPM(from: result.bestTranscription.formattedString)
                    }
                }

                // Apple caps recognition sessions at ~1 minute — restart automatically
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

        } catch {
            isListening = false
        }
    }

    func stopListening() {
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
    }

    // MARK: - Private

    /// Called when the recognizer emits a new partial or final transcription.
    /// Counts newly-spoken words and updates the rolling WPM estimate.
    private func updateWPM(from transcription: String) {
        let newWordCount = countNewWords(current: transcription, previous: lastTranscription)
        lastTranscription = transcription

        let now = Date()

        // Stamp each new word at the current time
        for _ in 0..<newWordCount {
            wordTimestamps.append(now)
        }

        // Drop timestamps outside the sliding window
        let cutoff = now.addingTimeInterval(-wpmWindowSeconds)
        wordTimestamps = wordTimestamps.filter { $0 > cutoff }

        // Need at least 3 words and > 1 second of data for a meaningful estimate
        guard wordTimestamps.count >= 3, let oldest = wordTimestamps.first else { return }
        let elapsed = now.timeIntervalSince(oldest)
        guard elapsed > 1 else { return }

        let rawWPM = Double(wordTimestamps.count) / elapsed * 60

        // Smooth with exponential moving average to avoid jitter
        estimatedWordsPerMinute = estimatedWordsPerMinute * 0.6 + rawWPM * 0.4
    }

    /// Returns how many new words appeared between two successive transcription strings.
    private func countNewWords(current: String, previous: String) -> Int {
        let currentCount = current.split(separator: " ").count
        let previousCount = previous.split(separator: " ").count
        return max(0, currentCount - previousCount)
    }

    /// Apple's on-device recognizer silently ends sessions after ~1 minute.
    /// Tear down and restart so voice scroll never drops out mid-script.
    private func restartListening() {
        guard isListening else { return }
        // Preserve the accumulated WPM so the display doesn't flicker to zero
        let preservedWPM = estimatedWordsPerMinute
        stopListening()
        isListening = true          // keep the flag true during the brief restart
        estimatedWordsPerMinute = preservedWPM
        startListening()
    }
}
