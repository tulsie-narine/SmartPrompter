import SwiftData
import SwiftUI

struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var script: Script
    @StateObject private var speechScrollController = SpeechScrollController()

    @State private var isPlaying = false
    @State private var scrollOffset: CGFloat = 0
    @State private var lastTick = Date()
    @State private var showingSettings = false

    private let timer = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    private var settings: PrompterSettings {
        script.settings
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                settings.backgroundColor
                    .ignoresSafeArea()

                prompterText(in: geometry)

                if settings.showMarker {
                    markerLine
                }

                controls
            }
            .statusBarHidden(true)
            .onAppear {
                ScriptStore.markUsed(script, in: modelContext)
                lastTick = Date()
            }
            .onDisappear {
                speechScrollController.stopListening()
            }
            .onReceive(timer) { tick in
                advanceScroll(at: tick)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsPanelView(
                    script: script,
                    speechScrollController: speechScrollController
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func prompterText(in geometry: GeometryProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            Text(script.body)
                .font(.system(size: settings.fontSize, weight: .semibold))
                .foregroundStyle(settings.fontColor)
                .multilineTextAlignment(.center)
                .lineSpacing(max(8, settings.fontSize * 0.28))
                .padding(.horizontal, settings.margins)
                .padding(.vertical, geometry.size.height * 0.42)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: settings.mirrorMode ? -1 : 1, y: 1)
                .offset(y: -scrollOffset)
                .animation(.smooth(duration: 0.2), value: settings.mirrorMode)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
    }

    private var markerLine: some View {
        Rectangle()
            .fill(settings.fontColor.opacity(0.28))
            .frame(height: 2)
            .overlay(alignment: .leading) {
                Circle()
                    .fill(settings.fontColor.opacity(0.65))
                    .frame(width: 10, height: 10)
                    .offset(x: -5)
            }
            .padding(.horizontal, 24)
            .allowsHitTesting(false)
    }

    private var controls: some View {
        VStack {
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Close")

                Text(script.title.isEmpty ? "Untitled Script" : script.title)
                    .font(.headline)
                    .lineLimit(1)
                    .foregroundStyle(settings.fontColor)

                Spacer(minLength: 12)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Settings")
            }
            .padding(10)
            .background(.thinMaterial, in: Capsule())

            Spacer()

            HStack(spacing: 16) {
                Button {
                    resetScroll()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Reset")

                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                        .frame(width: 58, height: 58)
                }
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .buttonStyle(.borderedProminent)

                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "textformat.size")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Display Settings")
            }
            .padding(10)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.bordered)
        .padding()
    }

    private func togglePlayback() {
        isPlaying.toggle()
        lastTick = Date()
    }

    private func resetScroll() {
        isPlaying = false
        withAnimation(.smooth(duration: 0.25)) {
            scrollOffset = 0
        }
    }

    private func advanceScroll(at tick: Date) {
        let elapsed = tick.timeIntervalSince(lastTick)
        lastTick = tick

        guard isPlaying else { return }

        let smartMultiplier: Double
        if settings.smartVoiceScroll, speechScrollController.isListening {
            smartMultiplier = max(0.6, min(1.6, speechScrollController.estimatedWordsPerMinute / 165))
        } else {
            smartMultiplier = 1
        }

        scrollOffset += CGFloat(settings.scrollSpeed * elapsed * smartMultiplier)
    }
}
