import AppKit
import SwiftUI

/// SwiftPM builds a bare executable, not an app bundle, so bring the window to the front ourselves.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("UnderLimit") {
            ContentView()
                .frame(minWidth: 560, minHeight: 420)
        }
    }
}
