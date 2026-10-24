import SwiftUI

@main
@MainActor
struct WristNoteAIApp: App {
    @StateObject private var model = PhoneModel()
    var body: some Scene {
        WindowGroup { ContentView(model: model, store: model.store, connectivity: model.connectivity) }
    }
}
