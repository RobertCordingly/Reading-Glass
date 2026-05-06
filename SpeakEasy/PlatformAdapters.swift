import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Cross-platform color aliases

extension Color {
    /// The window/page background color (nsColor.windowBackgroundColor on macOS, systemBackground on iOS).
    static var platformWindowBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }

    /// The secondary content background (nsColor.controlBackgroundColor on macOS, secondarySystemBackground on iOS).
    static var platformControlBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: - Cross-platform clipboard

enum PlatformClipboard {
    static func copyString(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }
}

// MARK: - Cross-platform image

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension Image {
    /// Convenience init for `NSImage` (macOS) or `UIImage` (iOS) without #ifs at the call site.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
