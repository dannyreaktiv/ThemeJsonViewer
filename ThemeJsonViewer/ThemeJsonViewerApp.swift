import SwiftUI

extension Notification.Name {
    static let openDirectory = Notification.Name("openDirectory")
}

@main
struct ThemeJsonViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Directory...") {
                    NotificationCenter.default.post(name: .openDirectory, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
