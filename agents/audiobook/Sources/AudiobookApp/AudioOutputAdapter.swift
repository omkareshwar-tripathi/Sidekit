import Foundation
import AVFoundation
import AudiobookCore

final class AudioOutputAdapter: AudioOutputPort {
    private var player: AVAudioPlayer?

    func load(_ fileName: String) {
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext,
                                          subdirectory: "Resources")
            ?? Bundle.module.url(forResource: base, withExtension: ext) else {
            print("audio resource not found: \(fileName)")
            player = nil
            return
        }
        player = try? AVAudioPlayer(contentsOf: url)
        player?.enableRate = true
        player?.prepareToPlay()
    }

    func play() { player?.play() }
    func pause() { player?.pause() }
    func seek(to seconds: TimeInterval) { player?.currentTime = min(seconds, player?.duration ?? seconds) }
    func setRate(_ rate: Double) { player?.rate = Float(rate) }
}
