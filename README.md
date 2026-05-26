# SmartCue

A clean, capable teleprompter for iPhone. SmartCue lets you read scripts hands-free with a smart voice scroll that listens to you in real time — speeding up when you speak faster, slowing down when you slow down, and pausing when you stop.

Built with SwiftUI and SwiftData. Fully open source.

---

## Features

### Smart Voice Scroll
SmartCue listens to your microphone while you read and drives the scroll automatically. It uses a real-time audio energy envelope (not speech recognition latency) to respond within ~50ms of your voice — so it starts the instant you speak, bridges natural gaps between words, and stops within ~350ms of a deliberate pause. Your speaking pace also modulates the scroll speed over time: faster speech scrolls faster, slower speech scrolls slower.

### Word Highlight
When Smart Voice Scroll is active, the next word to be spoken is highlighted in white with black text so you always know exactly where you are on the page.

### Mirror & Flip Modes
- **Mirror Mode** flips the text horizontally for use with a beam-splitter or reflective surface
- **Flip Vertical** flips the text upside-down so you can place your phone face-up on a surface and read the reflection in a mirror — no phone rotation needed

### Script Library
Create and manage multiple scripts. Each script remembers its own font size, scroll speed, colors, margins, and display settings independently.

### Per-Script Settings
Every script stores its own prompter configuration:
- Font size (24–96pt)
- Font and background color
- Scroll speed
- Side margins
- Reading marker line
- Mirror / flip display modes
- Smart Voice Scroll toggle

### Always-On Display
The screen stays on while the teleprompter is open so it never dims mid-read.

---

## Requirements

- iOS 17 or later
- iPhone (iPad layout not yet optimized)
- Microphone and Speech Recognition permissions required for Smart Voice Scroll

---

## Getting Started

### Build from Source

1. Clone the repo:
   ```bash
   git clone https://github.com/tulsie-narine/SmartPrompter.git
   cd SmartPrompter
   ```

2. Open the project in Xcode:
   ```
   SmartPrompter/SmartPrompter.xcodeproj
   ```

3. Select your iPhone as the run destination.

4. Set a development team in **Signing & Capabilities** (your Apple ID is enough for personal use).

5. Build and run (`⌘R`).

### First Run

On first launch, a sample script is created automatically. Tap it to open the teleprompter, press **Play**, and start reading — the scroll will follow your voice.

To use Smart Voice Scroll, open **Settings** (slider icon) while in the teleprompter, enable **Smart Voice Scroll**, and grant microphone and speech recognition permissions when prompted.

---

## Project Structure

```
SmartPrompter/
├── SmartPrompterApp.swift       # App entry point
├── Models/
│   ├── Script.swift             # SwiftData model for a script
│   └── PrompterSettings.swift   # Per-script display + behavior settings
├── Services/
│   ├── ScriptStore.swift        # SwiftData helpers (create, update, delete)
│   └── SpeechScrollController.swift  # Audio engine + voice scroll logic
└── Views/
    ├── ScriptLibraryView.swift  # Script list / home screen
    ├── ScriptEditorView.swift   # Script text editor
    ├── TeleprompterView.swift   # Full-screen prompter
    └── SettingsPanelView.swift  # Prompter settings sheet
```

---

## How Smart Voice Scroll Works

The scroll engine uses two independent signals:

**1. Audio energy envelope** — the primary driver. The microphone tap fires ~43 times per second. Each buffer's RMS amplitude is fed into an envelope follower (fast attack ~50ms, medium release ~350ms). When the envelope crosses the noise floor, scrolling starts; when it falls below, scrolling stops. This gives near-instant response with no speech recognition latency.

**2. Speech recognition pace** — a secondary modifier. Apple's `SFSpeechRecognizer` runs in parallel and measures your rolling words-per-minute over a 5-second window. This gently adjusts a pace multiplier (0.5× to 1.6×) so the scroll adapts to fast vs. slow speakers over time. The 1-minute session cap is handled transparently with a seamless restart.

The final `scrollSpeedMultiplier` = energy activity × pace multiplier. `TeleprompterView` multiplies this against the user's chosen scroll speed setting at 60fps.

---

## Contributing

Contributions are welcome. Some areas worth improving:

- iPad layout and split-screen support
- Landscape orientation
- iCloud sync for scripts across devices
- Custom fonts
- Support for additional speech recognition locales
- Accessibility improvements

Please open an issue before starting large changes so we can align on approach.

---

## License

MIT License. See [LICENSE](LICENSE) for details.

---

## Author

Built by [Tulsie Narine](https://github.com/tulsie-narine).
