import SwiftUI

struct SettingsView: View {
    @AppStorage(OrbDisplaySettings.show24hKey)
    private var show24h = true

    @AppStorage(OrbDisplaySettings.show48hKey)
    private var show48h = true

    var body: some View {
        Form {
            Section("悬浮小球") {
                Toggle("显示 24 小时重置概率", isOn: $show24h)
                Toggle("显示 48 小时重置概率", isOn: $show48h)

                Text("关闭后，小球会自动收紧排列；打开概率球仍会进入 codex-reset.com。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("刷新与动效") {
                Text("额度和概率数据每 5 分钟静默更新。鼠标移到额度球上时，会播放一次从 100% 收到当前值的读取动画。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .padding(.vertical, 12)
    }
}
