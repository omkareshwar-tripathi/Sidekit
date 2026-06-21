import Testing
import Foundation
@testable import AudiobookCore

struct SampleLibraryTests {
    @Test func libraryHasBooksWithChapters() {
        #expect(SampleLibrary.books.count >= 2)
        for book in SampleLibrary.books {
            #expect(book.chapters.count >= 3)
            #expect(book.chapters.first?.startTime == 0)
        }
    }

    @Test func initialStateIsPausedAtStart() {
        let s = PlayerState.initial(book: SampleLibrary.books[0])
        #expect(s.isPlaying == false)
        #expect(s.position == 0)
        #expect(s.speed == 1.0)
        #expect(s.currentChapter == 0)
    }

    @Test func currentChapterTracksPosition() {
        var s = PlayerState.initial(book: SampleLibrary.books[0]) // chapters at 0,60,120
        s.position = 70
        #expect(s.currentChapter == 1)
        s.position = 130
        #expect(s.currentChapter == 2)
    }
}
