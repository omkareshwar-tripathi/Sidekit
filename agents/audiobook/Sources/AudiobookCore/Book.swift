import Foundation

public struct Chapter: Equatable, Sendable {
    public let title: String
    public let startTime: TimeInterval   // seconds from the start of the book
    public init(title: String, startTime: TimeInterval) {
        self.title = title
        self.startTime = startTime
    }
}

public struct Book: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let author: String
    public let audioFileName: String     // bundled resource, e.g. "book-a.caf"
    public let duration: TimeInterval
    public let chapters: [Chapter]
    public init(id: String, title: String, author: String,
                audioFileName: String, duration: TimeInterval, chapters: [Chapter]) {
        self.id = id; self.title = title; self.author = author
        self.audioFileName = audioFileName; self.duration = duration; self.chapters = chapters
    }
}

public enum SampleLibrary {
    public static let books: [Book] = [
        Book(id: "meditations", title: "Meditations", author: "Marcus Aurelius",
             audioFileName: "book-a.caf", duration: 180,
             chapters: [Chapter(title: "Book I", startTime: 0),
                        Chapter(title: "Book II", startTime: 60),
                        Chapter(title: "Book III", startTime: 120)]),
        Book(id: "art-of-war", title: "The Art of War", author: "Sun Tzu",
             audioFileName: "book-b.caf", duration: 150,
             chapters: [Chapter(title: "Laying Plans", startTime: 0),
                        Chapter(title: "Waging War", startTime: 50),
                        Chapter(title: "The Sheathed Sword", startTime: 100)]),
    ]
}
