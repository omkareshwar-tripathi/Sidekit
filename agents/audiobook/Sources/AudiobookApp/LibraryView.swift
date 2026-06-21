import SwiftUI
import AudiobookCore

struct LibraryView: View {
    @ObservedObject var vm: PlayerViewModel

    var body: some View {
        HStack(spacing: 0) {
            List(SampleLibrary.books) { book in
                Button {
                    vm.switchBook(book.title)
                } label: {
                    VStack(alignment: .leading) {
                        Text(book.title).bold()
                        Text(book.author).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(width: 220)
            Divider()
            NowPlayingView(vm: vm)
        }
        .frame(minHeight: 360)
    }
}
