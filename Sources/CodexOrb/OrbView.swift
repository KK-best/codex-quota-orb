import CodexOrbCore
import SwiftUI

struct OrbView: View {
    @ObservedObject var monitor: UsageMonitor
    let onTap: () -> Void
    let onOpenReset: () -> Void
    let onDrag: (CGSize, Bool) -> Void

    @State private var hovering = false

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
                    Circle()
                        .fill(.ultraThinMaterial)

                    Circle()
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)

                    Circle()
                        .stroke(Color.primary.opacity(0.09), lineWidth: 5)
                        .padding(7)

                    Circle()
                        .trim(from: 0, to: remaining / 100)
                        .stroke(
                            AngularGradient(
                                colors: [accent.opacity(0.65), accent, accent.opacity(0.78)],
                                center: .center
                            ),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .padding(7)
                        .animation(.easeInOut(duration: 0.45), value: remaining)

                    VStack(spacing: -1) {
                        if let quota = monitor.account?.quota {
                            Text("\(Int(quota.remainingPercent.rounded()))")
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
            }
            .buttonStyle(.plain)
            .frame(width: 64, height: 64)
            .padding(4)
            .scaleEffect(hovering ? 1.045 : 1)
            .shadow(color: .black.opacity(hovering ? 0.22 : 0.15), radius: hovering ? 16 : 11, y: 7)
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

            probabilityOrb(
                value: monitor.resetProbability?.preferred24h,
                label: "24h",
                offset: 76
            )
            probabilityOrb(
                value: monitor.resetProbability?.model48h,
                label: "48h",
                offset: 152
            )
        }
        .frame(width: 80, height: 228, alignment: .top)
    }

    private func probabilityOrb(
        value: Double?,
        label: String,
        offset: CGFloat
    ) -> some View {
        let accent = probabilityAccent(value)
        return Button(action: onOpenReset) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)

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
        }
        .buttonStyle(.plain)
        .frame(width: 64, height: 64)
        .padding(4)
        .shadow(color: .black.opacity(0.15), radius: 11, y: 7)
        .contentShape(Circle())
        .help("打开 codex-reset.com · \(label) 重置概率")
        .accessibilityLabel("打开 Codex Reset")
        .accessibilityValue("\(label) 重置概率 \(probabilityText(value))")
        .offset(y: offset)
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
