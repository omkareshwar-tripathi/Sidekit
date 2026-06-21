import SwiftUI

@main
struct AudiobookAgentApp: App {
    @StateObject private var vm = PlayerViewModel()
    var body: some Scene {
        WindowGroup("Audiobook Agent") {
            LibraryView(vm: vm)
        }
    }
}
