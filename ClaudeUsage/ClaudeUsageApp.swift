import SwiftUI

@main
struct ClaudeUsageApp: App {
    // Polling starts at launch so the menu bar item has data even with the window closed.
    @State private var store: UsageStore = {
        let store = UsageStore()
        store.start()
        return store
    }()

    var body: some Scene {
        Window("Claude Usage", id: "main") {
            ContentView(layout: .window)
                .environment(store)
        }
        .defaultSize(width: 360, height: 420)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            ContentView(layout: .menuBar)
                .environment(store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
