// Headless verification that the bundled WhisperKit model loads and transcribes fully
// offline. Usage: swift run ModelSelftest <modelFolder> <audioPath>
@preconcurrency import WhisperKit
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write(Data("usage: ModelSelftest <modelFolder> <audioPath>\n".utf8))
    exit(2)
}
let modelFolder = args[1]
let audioPath = args[2]

let whisper = try await WhisperKit(WhisperKitConfig(modelFolder: modelFolder))
let results: [TranscriptionResult] = try await whisper.transcribe(audioPath: audioPath)
let text = results.map(\.text).joined(separator: " ")
print("TRANSCRIPT: \(text)")
