import AVFoundation
import Foundation
import WhisperKit

@MainActor
final class TranscriptionViewModel: ObservableObject {
    @Published var liveTranscriptText: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String?
    @Published var lastSavedFilePath: String?

    private let audioEngine = AVAudioEngine()
    private let session = AVAudioSession.sharedInstance()

    private var whisperKit: WhisperKit?
    private var streamingTask: Task<Void, Never>?

    // Fixed-size FIFO buffer for model-ready Float samples.
    // This prevents retaining all raw audio in memory.
    private var pendingSamples: [Float] = []
    private let processingChunkSize = 16_000 // ~1 second at 16kHz.

    func startTranscription() async {
        errorMessage = nil
        lastSavedFilePath = nil

        do {
            try await requestMicrophonePermission()
            try configureAudioSession()
            try await loadModelIfNeeded()
            try startAudioCapturePipeline()
            isRecording = true
            startStreamingLoop()
        } catch {
            isRecording = false
            errorMessage = error.localizedDescription
        }
    }

    func stopTranscription() async {
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        streamingTask?.cancel()
        streamingTask = nil
        isRecording = false

        do {
            let url = try saveTranscriptToDisk(liveTranscriptText)
            lastSavedFilePath = url.path
        } catch {
            errorMessage = "Failed to save transcript: \(error.localizedDescription)"
        }
    }

    private func requestMicrophonePermission() async throws {
        let granted = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }

        guard granted else {
            throw NSError(
                domain: "WhisperPad",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Enable it in Settings to continue."]
            )
        }
    }

    private func configureAudioSession() throws {
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw NSError(
                domain: "WhisperPad",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Audio session setup failed: \(error.localizedDescription)"]
            )
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            self.handleInterruption(note)
        }
    }

    private func loadModelIfNeeded() async throws {
        if whisperKit != nil { return }

        do {
            // NOTE: replace with the model variant you distribute.
            whisperKit = try await WhisperKit(model: "openai_whisper-small")
        } catch {
            throw NSError(
                domain: "WhisperPad",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Whisper model failed to load/download: \(error.localizedDescription)"]
            )
        }
    }

    private func startAudioCapturePipeline() throws {
        let input = audioEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // Audio pipeline notes:
        // 1) AVAudioEngine tap captures small PCM buffers continuously from mic.
        // 2) Each buffer is converted to mono Float samples.
        // 3) Samples are appended to a bounded FIFO array.
        // 4) Streaming loop pops fixed-size chunks and sends to WhisperKit.
        // This chunked flow avoids holding full-session audio in memory.
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0, let channelData = buffer.floatChannelData else { return }

            // Down-mix to mono by taking first channel.
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

            Task { @MainActor in
                self.pendingSamples.append(contentsOf: samples)
                let maxBuffer = self.processingChunkSize * 20 // Cap FIFO size to ~20 seconds.
                if self.pendingSamples.count > maxBuffer {
                    self.pendingSamples.removeFirst(self.pendingSamples.count - maxBuffer)
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw NSError(
                domain: "WhisperPad",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start audio engine: \(error.localizedDescription)"]
            )
        }
    }

    private func startStreamingLoop() {
        streamingTask?.cancel()
        streamingTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard isRecording else { break }

                if pendingSamples.count >= processingChunkSize,
                   let whisperKit {
                    let chunk = Array(pendingSamples.prefix(processingChunkSize))
                    pendingSamples.removeFirst(processingChunkSize)

                    do {
                        let result = try await whisperKit.transcribe(audioArray: chunk)
                        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty {
                            if liveTranscriptText.isEmpty {
                                liveTranscriptText = text
                            } else {
                                liveTranscriptText += "\n" + text
                            }
                        }
                    } catch {
                        errorMessage = "Transcription error: \(error.localizedDescription)"
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 80_000_000)
                }
            }
        }
    }

    private func handleInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        if type == .began {
            errorMessage = "Audio session interrupted (e.g. call or system event)."
            Task { await stopTranscription() }
        }
    }

    private func saveTranscriptToDisk(_ transcript: String) throws -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateStamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let fileURL = docs.appendingPathComponent("Transcript-\(dateStamp).txt")
        try transcript.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
