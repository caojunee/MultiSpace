import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var lock: AppLock
    @EnvironmentObject private var spaceStore: SpaceStore
    @EnvironmentObject private var vault: VaultStore

    @State private var confirmingWipe = false
    @State private var wipeMessage: String?

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = info?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }

    var body: some View {
        List {
            if let wipeMessage = wipeMessage {
                Section {
                    Text(wipeMessage).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("隐私") {
                Toggle("应用锁", isOn: $lock.enabled)
                Text("开启后每次 App 回到前台都需要通过面容 ID / 指纹 / 设备密码解锁。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("它是怎么工作的") {
                Label("每个空间使用 iOS 17+ 的独立持久化网站数据仓库。", systemImage: "square.stack.3d.up")
                Label("Cookie、localStorage、缓存彼此隔离，重启后登录态保留。", systemImage: "clock.arrow.circlepath")
                Label("空间里打开的是网站网页版，不是原生 App 的副本。", systemImage: "globe")
                Label("密码存在系统钥匙串，查看需要生物识别。", systemImage: "key.horizontal")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            Section("数据") {
                LabeledContent("空间数量", value: "\(spaceStore.spaces.count)")
                LabeledContent("保存的账号", value: "\(vault.items.count)")
                Button(role: .destructive) { confirmingWipe = true } label: {
                    Label("删除所有空间", systemImage: "trash")
                }
                .disabled(spaceStore.spaces.isEmpty)
            }

            Section("关于") {
                LabeledContent("版本", value: versionText)
                LabeledContent("最低系统", value: "iOS 17.0")
                Text("MultiSpace 是面向网页版服务的多账号工作台，不提供、也不声称提供任何第三方原生应用的分身或多开能力。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Text("上架提示：App Store 审核对「应用分身 / 多开」类表述敏感（4.3 / 5.2.1）。提交审核时请以「多账号网页工作台」定位描述，界面文案不要出现「微信双开」等字样。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("合规说明")
            }
        }
        .navigationTitle("设置")
        .alert("删除所有空间？", isPresented: $confirmingWipe) {
            Button("取消", role: .cancel) {}
            Button("全部删除", role: .destructive) { wipeAll() }
        } message: {
            Text("所有空间的登录状态与网站数据会被清除，保险箱账号保留。")
        }
    }

    private func wipeAll() {
        let snapshot = spaceStore.spaces
        guard !snapshot.isEmpty else { return }
        var remaining = snapshot.count
        var failures = 0
        // delete 的回调统一回到主线程，串行累加即可，不需要并发原语
        for space in snapshot {
            spaceStore.delete(space) { ok, _ in
                if !ok { failures += 1 }
                remaining -= 1
                if remaining == 0 {
                    wipeMessage = failures == 0
                        ? "已删除 \(snapshot.count) 个空间"
                        : "已删除，但 \(failures) 个空间的数据清理失败"
                }
            }
        }
    }
}
