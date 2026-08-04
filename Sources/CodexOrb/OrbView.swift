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
    @State private var displayed24h: Double?
    @State private var displayed48h: Double?
    @State private var mainHoverSequence = 0
    @State private var probabilityHoverSequence = 0
    @AppStorage(OrbDisplaySettings.show24hKey)
    private var show24h = true
    @AppStorage(OrbDisplaySettings.show48hKey)
    private var show48h = true

    private var remaining: Double {
        monitor.account?.quota.remainingPercent ?? 0
    }

    private var probability24h: Double? {
        monitor.resetProbability?.preferred24h
    }

    private var probability48h: Double? {
        monitor.resetProbability?.model48h
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
                    value: displayed24h,
                    actualValue: probability24h,
                    label: "24h",
                    offset: OrbDisplaySettings.orbStep
                )
            }
            if show48h {
                probabilityOrb(
                    value: displayed48h,
                    actualValue: probability48h,
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
            displayed24h = probability24h
            displayed48h = probability48h
            onHeightChange(
                OrbDisplaySettings.panelHeight(show24h: show24h, show48h: show48h)
            )
        }
        .onChange(of: remaining) { _, value in
            if !hovering {
                withAnimation(.easeInOut(duration: 0.45)) {
                    displayedRemaining = value
                }
            }
        }
        .onChange(of: hovering) { _, isHovering in
            if isHovering {
                startMainHoverSequence()
            } else {
                stopMainHoverSequence()
            }
        }
        .onChange(of: probability24h) { _, value in
            if hoveredProbability != "24h" {
                withAnimation(.easeInOut(duration: 0.45)) {
                    displayed24h = value
                }
            }
        }
        .onChange(of: probability48h) { _, value in
            if hoveredProbability != "48h" {
                withAnimation(.easeInOut(duration: 0.45)) {
                    displayed48h = value
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
        actualValue: Double?,
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
            if isHovering {
                startProbabilityHoverSequence(label: label, value: actualValue)
            } else {
                stopProbabilityHoverSequence(label: label)
            }
        }
        .contentShape(Circle())
        .help("打开 codex-reset.com · \(label) 重置概率")
        .accessibilityLabel("打开 Codex Reset")
        .accessibilityValue("\(label) 重置概率 \(probabilityText(value))")
        .offset(y: offset)
    }

    private func startMainHoverSequence() {
        guard monitor.account != nil else { return }

        mainHoverSequence &+= 1
        let sequenceID = mainHoverSequence

        withAnimation(.easeInOut(duration: 0.28)) {
            displayedRemaining = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard sequenceID == mainHoverSequence, hovering else { return }
            withAnimation(.easeInOut(duration: 0.52)) {
                displayedRemaining = 100
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) {
            guard sequenceID == mainHoverSequence, hovering else { return }
            withAnimation(.easeOut(duration: 0.56)) {
                displayedRemaining = remaining
            }
        }
    }

    private func stopMainHoverSequence() {
        mainHoverSequence &+= 1
        withAnimation(.easeOut(duration: 0.20)) {
            displayedRemaining = remaining
        }
    }

    private func startProbabilityHoverSequence(label: String, value: Double?) {
        guard value != nil else { return }

        probabilityHoverSequence &+= 1
        let sequenceID = probabilityHoverSequence

        withAnimation(.easeInOut(duration: 0.28)) {
            setDisplayedProbability(0, for: label)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
            guard sequenceID == probabilityHoverSequence,
                  hoveredProbability == label else { return }
            withAnimation(.easeInOut(duration: 0.52)) {
                setDisplayedProbability(100, for: label)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.88) {
            guard sequenceID == probabilityHoverSequence,
                  hoveredProbability == label else { return }
            withAnimation(.easeOut(duration: 0.56)) {
                setDisplayedProbability(currentProbability(for: label), for: label)
            }
        }
    }

    private func stopProbabilityHoverSequence(label: String) {
        probabilityHoverSequence &+= 1
        withAnimation(.easeOut(duration: 0.20)) {
            setDisplayedProbability(currentProbability(for: label), for: label)
        }
    }

    private func currentProbability(for label: String) -> Double? {
        switch label {
        case "24h":
            return probability24h
        case "48h":
            return probability48h
        default:
            return nil
        }
    }

    private func setDisplayedProbability(_ value: Double?, for label: String) {
        switch label {
        case "24h":
            displayed24h = value
        case "48h":
            displayed48h = value
        default:
            break
        }
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
