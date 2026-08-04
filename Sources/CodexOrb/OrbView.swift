import CodexOrbCore
import SwiftUI

struct OrbView: View {
    @ObservedObject var monitor: UsageMonitor
    let onTap: () -> Void
    let onOpenReset: () -> Void
    let onDrag: (CGSize, Bool) -> Void
    let onHeightChange: (CGFloat) -> Void

    @State private var hovering = false
    @State private var hoveredProbability: String?
    @State private var displayedRemaining = 0.0
    @AppStorage(OrbDisplaySettings.show24hKey)
    private var show24h = true
    @AppStorage(OrbDisplaySettings.show48hKey)
    private var show48h = true

    private var remaining: Double {
        monitor.account?.quota.remainingPercent ?? 0
    }

    private var accent: Color {
        guard let severity = monitor.account?.quota.severity else {
            return Color(nsColor: .systemGray)
        }
        switch severity {
        case .normal:
            return Color(nsColor: .systemBlue)
        case .warning:
            return Color(nsColor: .systemOrange)
        case .critical:
            return Color(nsColor: .systemRed)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Button(action: onTap) {
                ZStack {
                    orbFill

                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)

                    Circle()
                        .stroke(Color.primary.opacity(0.09), lineWidth: 5)
                        .padding(7)

                    Circle()
                        .trim(from: 0, to: displayedRemaining / 100)
                        .stroke(
                            AngularGradient(
                                colors: [accent.opacity(0.65), accent, accent.opacity(0.78)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                        .animation(.easeInOut(duration: 0.45), value: displayedRemaining)

                    VStack(spacing: -1) {
                        if monitor.account != nil {
                            AnimatedIntegerText(value: displayedRemaining)
                                .font(.system(size: 21, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("% 余量")
                                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        } else if monitor.isRefreshingAccount {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "exclamationmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Circle()
                        .fill(monitor.accountError == nil ? accent : Color(nsColor: .systemRed))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                        .offset(x: 22, y: -21)
                }
                .compositingGroup()
                .shadow(
                    color: .black.opacity(hovering ? 0.18 : 0.11),
                    radius: hovering ? 10 : 7,
                    y: 5
                )
            }
            .buttonStyle(.plain)
            .frame(width: 64, height: 64)
            .padding(4)
            .scaleEffect(hovering ? 1.045 : 1)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .simultaneousGesture(
                DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .onChanged { onDrag($0.translation, false) }
                    .onEnded { onDrag($0.translation, true) }
            )
            .accessibilityLabel("Codex 剩余额度")
            .accessibilityValue(
                monitor.account.map {
                    "\(Int($0.quota.remainingPercent.rounded()))%，\(monitor.isDashboardPresented ? "已展开" : "已收起")"
                } ?? "不可用"
            )

            if show24h {
                probabilityOrb(
                    value: monitor.resetProbability?.preferred24h,
                    label: "24h",
                    offset: OrbDisplaySettings.orbStep
                )
            }
            if show48h {
                probabilityOrb(
                    value: monitor.resetProbability?.model48h,
                    label: "48h",
                    offset: OrbDisplaySettings.orbStep * (show24h ? 2 : 1)
                )
            }
        }
        .frame(
            width: OrbDisplaySettings.panelWidth,
            height: OrbDisplaySettings.panelHeight(show24h: show24h, show48h: show48h),
            alignment: .top
        )
        .onAppear {
            displayedRemaining = remaining
            onHeightChange(
                OrbDisplaySettings.panelHeight(show24h: show24h, show48h: show48h)
            )
        }
        .onChange(of: remaining) { _, value in
            if !hovering {
                displayedRemaining = value
            }
        }
        .onChange(of: hovering) { _, isHovering in
            guard monitor.account != nil else { return }
            if isHovering {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    displayedRemaining = 100
                }
                withAnimation(.easeOut(duration: 0.72)) {
                    displayedRemaining = remaining
                }
            } else {
                withAnimation(.easeOut(duration: 0.16)) {
                    displayedRemaining = remaining
                }
            }
        }
        .onChange(of: show24h) { _, _ in
            onHeightChange(
                OrbDisplaySettings.panelHeight(show24h: show24h, show48h: show48h)
            )
        }
        .onChange(of: show48h) { _, _ in
            onHeightChange(
                OrbDisplaySettings.panelHeight(show24h: show24h, show48h: show48h)
            )
        }
    }

    private func probabilityOrb(
        value: Double?,
        label: String,
        offset: CGFloat
    ) -> some View {
        let accent = probabilityAccent(value)
        let isHovered = hoveredProbability == label
        return Button(action: onOpenReset) {
            ZStack {
                orbFill

                Circle()
                    .stroke(Color.white.opacity(0.34), lineWidth: 1)

                Circle()
                    .stroke(Color.primary.opacity(0.09), lineWidth: 5)
                    .padding(7)

                Circle()
                    .trim(from: 0, to: (value ?? 0) / 100)
                    .stroke(
                        AngularGradient(
                            colors: [
                                accent.opacity(0.65),
                                accent,
                                accent.opacity(0.78)
                            ],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(7)
                    .animation(.easeInOut(duration: 0.45), value: value)

                if monitor.isRefreshingResetProbability,
                   monitor.resetProbability == nil {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    VStack(spacing: -1) {
                        Text(probabilityText(value))
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(label)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .compositingGroup()
            .shadow(
                color: .black.opacity(isHovered ? 0.16 : 0.11),
                radius: isHovered ? 10 : 7,
                y: 5
            )
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .padding(4)
        .scaleEffect(isHovered ? 1.045 : 1)
        .animation(.easeOut(duration: 0.18), value: isHovered)
        .onHover { isHovering in
            hoveredProbability = isHovering ? label : nil
        }
        .contentShape(Circle())
        .help("打开 codex-reset.com · \(label) 重置概率")
        .accessibilityLabel("打开 Codex Reset")
        .accessibilityValue("\(label) 重置概率 \(probabilityText(value))")
        .offset(y: offset)
    }

    private var orbFill: some View {
        Circle()
            // A shape-colour surface avoids the rectangular edge that AppKit can
            // expose when a SwiftUI material is hosted in a clear NSPanel.
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.84))
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.045))
            )
            .clipShape(Circle())
    }

    private func probabilityText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private func probabilityAccent(_ value: Double?) -> Color {
        guard let value else {
            return Color(nsColor: .systemGray)
        }
        if value >= 60 {
            return Color(nsColor: .systemGreen)
        }
        if value >= 30 {
            return Color(nsColor: .systemOrange)
        }
        return Color.accentColor
    }
}

private struct AnimatedIntegerText: View, Animatable {
    var value: Double

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text("\(Int(value.rounded()))")
    }
}
