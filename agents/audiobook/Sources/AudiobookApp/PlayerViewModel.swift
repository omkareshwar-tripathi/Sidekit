import Foundation
import Combine
import AudiobookCore

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var state: PlayerState
    private let store: PlayerStore
    private var refresh: Timer?

    init() {
        let s = PlayerStore(book: SampleLibrary.books[0],
                            audio: AudioOutputAdapter(), clock: SystemClock())
        self.store = s
        self.state = s.state
    }

    private func sync() { state = store.state }

    func play()  { store.play();  startRefresh(); sync() }
    func pause() { store.pause(); stopRefresh();  sync() }
    func skipForward()  { store.skipForward();  sync() }
    func skipBackward() { store.skipBackward(); sync() }
    func nextChapter()  { store.nextChapter();  sync() }
    func previousChapter() { store.previousChapter(); sync() }
    func goToChapter(_ n: Int) { store.goToChapter(n); sync() }
    func setSpeed(_ r: Double) { store.setSpeed(r); sync() }
    func setSleepTimer(minutes: Int) { store.setSleepTimer(minutes: minutes); sync() }
    func setSleepTimerEndOfChapter() { store.setSleepTimerEndOfChapter(); sync() }
    func cancelSleepTimer() { store.cancelSleepTimer(); sync() }
    func switchBook(_ title: String) { store.switchBook(title: title); sync() }

    private func startRefresh() {
        guard refresh == nil else { return }
        refresh = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }
    private func stopRefresh() { refresh?.invalidate(); refresh = nil }
}
