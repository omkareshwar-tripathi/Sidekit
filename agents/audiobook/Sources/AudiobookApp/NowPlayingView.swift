import SwiftUI
import AudiobookCore

struct NowPlayingView: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        let s = vm.state
        VStack(spacing: 16) {
            Text(s.currentBook.title).font(.title2).bold()
            Text(s.currentBook.author).foregroundStyle(.secondary)
            Text("Chapter \(s.currentChapter + 1): \(s.currentBook.chapters[s.currentChapter].title)")
            Text(timeString(s.position) + " / " + timeString(s.currentBook.duration))
                .monospacedDigit()

            HStack(spacing: 12) {
                Button("⏪ 30") { vm.skipBackward() }
                Button(s.isPlaying ? "⏸ Pause" : "▶︎ Play") { s.isPlaying ? vm.pause() : vm.play() }
                Button("30 ⏩") { vm.skipForward() }
            }
            HStack(spacing: 12) {
                Button("⏮ Chapter") { vm.previousChapter() }
                Button("Chapter ⏭") { vm.nextChapter() }
            }
            HStack(spacing: 8) {
                Text("Speed \(String(format: "%.1f×", s.speed))")
                ForEach([0.75, 1.0, 1.5, 2.0], id: \.self) { r in
                    Button(String(format: "%.2g×", r)) { vm.setSpeed(r) }
                }
            }
            HStack(spacing: 8) {
                Button("Sleep 15m") { vm.setSleepTimer(minutes: 15) }
                Button("Sleep: end of chapter") { vm.setSleepTimerEndOfChapter() }
                Button("Cancel sleep") { vm.cancelSleepTimer() }
            }
            if let t = s.sleepTimer {
                Text("Sleep timer set (fires at \(timeString(t.fireAt)))").font(.caption)
            }
        }
        .padding()
        .frame(minWidth: 420)
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
