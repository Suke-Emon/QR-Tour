import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = TranscriptionViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Text("WhisperPad Transcriber")
                .font(.title2)
                .fontWeight(.semibold)

            HStack(spacing: 12) {
                Button("Start") {
                    Task { await viewModel.startTranscription() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isRecording)

                Button("Stop") {
                    Task { await viewModel.stopTranscription() }
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.isRecording)
            }

            ScrollView {
                Text(viewModel.liveTranscriptText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let savePath = viewModel.lastSavedFilePath {
                Text("Saved transcript: \(savePath)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
