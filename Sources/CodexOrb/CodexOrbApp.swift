import AppKit
import SwiftUI

@main
struct CodexOrbApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = UsageMonitor()
    private var coordinator: WindowCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        UserDefaults.standard.register(defaults: [
            OrbDisplaySettings.show24hKey: true,
            OrbDisplaySettings.show48hKey: true
        ])
        let coordinator = WindowCoordinator(monitor: monitor)
        coordinator.showOrb()
        self.coordinator = coordinator
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }
}
