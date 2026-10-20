import SwiftUI
import CoreText

@main
struct ScribbleScoutApp: App {
    @StateObject private var notebook = NotebookStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        if let url = Bundle.main.url(forResource: "Caveat", withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

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
