import AppKit
import SwiftUI

@MainActor
final class WindowCoordinator {
    private let monitor: UsageMonitor
    private var orbPanel: NSPanel?
    private var dashboardPanel: NSPanel?
    private var dragOrigin: NSPoint?
    private var escapeMonitor: Any?

    init(monitor: UsageMonitor) {
        self.monitor = monitor
    }

    func showOrb() {
        let panel = NSPanel(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: OrbDisplaySettings.panelWidth,
                height: OrbDisplaySettings.panelHeight
            ),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = false

        let rootView = OrbView(
            monitor: monitor,
            onTap: { [weak self] in
                self?.toggleDashboard()
            },
            onOpenReset: {
                guard let url = URL(string: "https://codex-reset.com/") else {
                    return
                }
                NSWorkspace.shared.open(url)
            },
            onDrag: { [weak self] translation, ended in
                self?.moveOrb(translation: translation, ended: ended)
            },
            onHeightChange: { [weak self] height in
                self?.resizeOrbPanel(height: height)
            }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        restorePosition(for: panel)
        panel.orderFrontRegardless()
        orbPanel = panel
    }

    func closeDashboard() {
        guard let panel = dashboardPanel, panel.isVisible else { return }
        monitor.setDashboardPresented(false)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func toggleDashboard() {
        if let dashboardPanel, dashboardPanel.isVisible {
            closeDashboard()
            return
        }

        let panel = dashboardPanel ?? makeDashboardPanel()
        positionDashboard(panel)
        monitor.setDashboardPresented(true)
        panel.alphaValue = 0
        NSApplication.shared.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func makeDashboardPanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 620),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true

        panel.contentView = NSHostingView(
            rootView: DashboardView(
                monitor: monitor,
                onClose: { [weak self] in
                    self?.closeDashboard()
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
        )

        dashboardPanel = panel
        installEscapeMonitor()
        return panel
    }

    private func positionDashboard(_ panel: NSPanel) {
        guard let orbPanel else { return }
        let orbFrame = orbPanel.frame
        let screen = orbPanel.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let spacing: CGFloat = 12

        var x = orbFrame.minX - panel.frame.width - spacing
        if x < visible.minX {
            x = orbFrame.maxX + spacing
        }
        x = min(max(x, visible.minX + 8), visible.maxX - panel.frame.width - 8)

        var y = orbFrame.midY - panel.frame.height / 2
        y = min(max(y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func moveOrb(translation: CGSize, ended: Bool) {
        guard let panel = orbPanel else { return }
        if dragOrigin == nil {
            dragOrigin = panel.frame.origin
        }
        guard let dragOrigin else { return }

        var proposed = NSPoint(
            x: dragOrigin.x + translation.width,
            y: dragOrigin.y - translation.height
        )
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            proposed.x = min(
                max(proposed.x, visible.minX + 4),
                visible.maxX - panel.frame.width - 4
            )
            proposed.y = min(
                max(proposed.y, visible.minY + 4),
                visible.maxY - panel.frame.height - 4
            )
        }

        panel.setFrameOrigin(proposed)
        if let dashboardPanel, dashboardPanel.isVisible {
            positionDashboard(dashboardPanel)
        }

        if ended {
            savePosition(panel.frame.origin)
            self.dragOrigin = nil
        }
    }

    private func resizeOrbPanel(height: CGFloat) {
        guard let panel = orbPanel else { return }
        guard abs(panel.frame.height - height) > 0.5 else { return }

        var frame = panel.frame
        let maxY = frame.maxY
        frame.size.height = height
        frame.origin.y = maxY - height
        panel.setFrame(frame, display: true, animate: true)

        if let dashboardPanel, dashboardPanel.isVisible {
            positionDashboard(dashboardPanel)
        }
    }

    private func restorePosition(for panel: NSPanel) {
        let defaults = UserDefaults.standard
        let storedX = defaults.object(forKey: "orb.position.x") as? Double
        let storedY = defaults.object(forKey: "orb.position.y") as? Double

        if let storedX, let storedY {
            panel.setFrameOrigin(NSPoint(x: storedX, y: storedY))
            return
        }

        let visible = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(
            NSPoint(
                x: visible.maxX - panel.frame.width - 28,
                y: visible.midY - panel.frame.height / 2
            )
        )
    }

    private func savePosition(_ point: NSPoint) {
        UserDefaults.standard.set(point.x, forKey: "orb.position.x")
        UserDefaults.standard.set(point.y, forKey: "orb.position.y")
    }

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            if event.keyCode == 53 {
                self?.closeDashboard()
                return nil
            }
            return event
        }
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
