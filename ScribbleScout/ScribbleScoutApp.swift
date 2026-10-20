import SwiftUI

@main
struct ScribbleScoutApp: App {
    @StateObject private var notebook = NotebookStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NotebookView(store: notebook)
                .tint(Color.accentColor)
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { notebook.current?.flush() }
                }
        }
    }
}
