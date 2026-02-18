import SwiftUI

extension Notification.Name {
    static let openCleanupLog = Notification.Name("openCleanupLog")
}

@main
struct SpeakEasyApp: App {
    init() {
        // Clear stale toolbar customization from previous versions
        UserDefaults.standard.removeObject(forKey: "NSToolbar Configuration main")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 500)
        .commands {
            CommandGroup(after: .windowList) {
                Button("AI Cleanup Log") {
                    NotificationCenter.default.post(name: .openCleanupLog, object: nil)
                }
            }
        }
    }
}
