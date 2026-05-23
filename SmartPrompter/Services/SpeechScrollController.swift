import Combine
import Foundation

@MainActor
final class SpeechScrollController: ObservableObject {
    enum PermissionState: String {
        case notRequested = "Not Requested"
        case placeholderGranted = "Ready"
    }

    @Published private(set) var estimatedWordsPerMinute: Double = 0
    @Published private(set) var isListening = false
    @Published private(set) var permissionState: PermissionState = .notRequested

    func requestPermissions() async -> Bool {
        // TODO: Request SFSpeechRecognizer authorization and AVAudioSession record permission here.
        permissionState = .placeholderGranted
        return true
    }

    func startListening() {
        // TODO: Start AVAudioEngine input and feed audio buffers into the speech recognizer here.
        isListening = true
        estimatedWordsPerMinute = 165
    }

    func stopListening() {
        // TODO: Stop AVAudioEngine, end the recognition request, and clear alignment state here.
        isListening = false
        estimatedWordsPerMinute = 0
    }
}
