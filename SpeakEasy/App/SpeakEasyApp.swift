import SwiftUI

extension Notification.Name {
    static let openCleanupLog = Notification.Name("openCleanupLog")
}

@main
struct SpeakEasyApp: App {
    init() {
        // Clear stale toolbar customization from previous versions
        //for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix("NSToolbar Configuration") {
        //    UserDefaults.standard.removeObject(forKey: key)
        //}
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        //.windowToolbarStyle(.unified)
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
