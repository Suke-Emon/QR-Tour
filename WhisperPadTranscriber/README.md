# WhisperPadTranscriber (iPadOS 18+)

SwiftUI iPad app for real-time, offline transcription using [WhisperKit](https://github.com/argmaxinc/WhisperKit).

## Features
- Start/Stop recording UI.
- AVAudioEngine microphone capture.
- Chunked transcription pipeline (no full raw-audio retention).
- Live transcript rendering in a scroll view.
- Transcript persisted to local `.txt` file on stop.
- Error handling for permission, model load, and interruptions.

## Open in Xcode
1. Open `WhisperPadTranscriber.xcodeproj` in Xcode 16+.
2. Set your Apple Development Team in target signing.
3. Plug in a physical iPad running iPadOS 18+.
4. Build and run.

## Notes
- First run may download the Whisper model (network required once).
- After model download, inference runs fully on-device.
