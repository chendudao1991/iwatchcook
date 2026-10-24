import SwiftUI

@MainActor
final class WatchModel: ObservableObject {
    let library: WatchLibrary
    let connectivity: WatchConnectivityManager
    let recorder: WatchRecordingService

    init() {
        let library = WatchLibrary()
        self.library = library
        let connectivity = WatchConnectivityManager(library: library)
        self.connectivity = connectivity
        recorder = WatchRecordingService(library: library, connectivity: connectivity)
    }
}

@main
@MainActor
struct WristNoteWatchApp: App {
    @StateObject private var model = WatchModel()
    var body: some Scene {
        WindowGroup {
            WatchHomeView(recorder: model.recorder, library: model.library, connectivity: model.connectivity)
        }
    }
}
