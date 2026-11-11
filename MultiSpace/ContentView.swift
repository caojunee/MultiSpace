import SwiftUI

private enum ContentAlert: Identifiable {
    case delete(Space)
    case notice(String)
    var id: String {
        switch self {
        case .delete(let space): return "delete-" + space.id.uuidString
        case .notice(let text): return "notice-" + text
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var spaceStore: SpaceStore
    @EnvironmentObject private var lock: AppLock

    @State private var showingAdd = false
    @State private var activeSpace: Space?
    @State private var editingSpace: Space?
    @State private var alertItem: ContentAlert?

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 18)]

    var body: some View {
        TabView {
            NavigationStack {
                ScrollView {
                    if spaceStore.spaces.isEmpty {
                        EmptyStateView { showingAdd = true }
                            .padding(.top, 70)
                    } else {
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(spaceStore.spaces) { space in
                                SpaceCard(space: space) { activeSpace = space }
                                    .contextMenu {
                                        Button { editingSpace = space } label: {
                                            Label("编辑", systemImage: "pencil")
                                        }
                                        Button {
                                            spaceStore.resetWebsiteData(for: space) {
                                                alertItem = .notice("「\(space.name)」的登录状态已清除")
                                            }
                                        } label: {
                                            Label("退出登录 / 清除数据", systemImage: "arrow.counterclockwise")
                                        }
                                        Divider()
                                        Button(role: .destructive) { alertItem = .delete(space) } label: {
                                            Label("删除空间", systemImage: "trash")
                                        }
                                    }
                            }
                            AddSpaceCard { showingAdd = true }
                        }
                        .padding(20)
                    }

                    Text("每个空间拥有独立的 Cookie、localStorage 与缓存，同一网站可同时登录多个账号，互不干扰。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                        .padding(.top, 12)
                }
                .navigationTitle("我的空间")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showingAdd = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
                .sheet(isPresented: $showingAdd) { AddSpaceView() }
                .sheet(item: $editingSpace) { space in EditSpaceView(space: space) }
                .fullScreenCover(item: $activeSpace) { space in
                    WebSpaceScreen(space: space)
                }
                .alert(item: $alertItem) { item in
                    switch item {
                    case .delete(let space):
                        return Alert(
                            title: Text("删除「\(space.name)」？"),
                            message: Text("该空间的所有登录状态、Cookie 与本地数据将一并清除，无法恢复。"),
                            primaryButton: .destructive(Text("删除")) {
                                activeSpace = nil
                                spaceStore.delete(space) { ok, message in
                                    if !ok {
                                        alertItem = .notice(message ?? "网站数据清理失败（空间已移除）")
                                    }
                                }
                            },
                            secondaryButton: .cancel()
                        )
                    case .notice(let text):
                        return Alert(title: Text("提示"), message: Text(text),
                                     dismissButton: .default(Text("好")))
                    }
                }
            }
            .tabItem { Label("空间", systemImage: "square.grid.2x2") }

            NavigationStack { VaultView() }
                .tabItem { Label("保险箱", systemImage: "lock.shield") }

            NavigationStack { SettingsView() }
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .overlay {
            if lock.isLocked { LockOverlay() }
        }
    }
}

// MARK: - 卡片

private struct SpaceCard: View {
    let space: Space
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(space.color.opacity(0.16))
                    Image(systemName: space.symbol)
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(space.color)
                }
                .frame(width: 76, height: 76)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(.green)
                        .frame(width: 9, height: 9)
                        .padding(7)
                }
                Text(space.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(space.site.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct AddSpaceCard: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.35),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 76, height: 76)
                Text("新建空间").font(.subheadline.weight(.medium))
                Text(" ").font(.caption2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptyStateView: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 54))
                .foregroundStyle(.tint)
            Text("还没有空间").font(.title3.weight(.semibold))
            Text("新建一个空间，给同一个网站配一份独立的登录环境。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)
            Button("新建第一个空间", action: onAdd).buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - 新建 / 编辑

private let palette = ["25A65B", "229ED9", "1772F6", "7C5CFC", "E5323D", "FF9500", "161823", "64748B"]

struct AddSpaceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spaceStore: SpaceStore

    @State private var site: Site = SiteCatalog.all[0]
    @State private var name = ""
    @State private var customURL = "https://"
    @State private var tint = "1772F6"

    var body: some View {
        NavigationStack {
            Form {
                Section("选择网站") {
                    Picker("网站", selection: $site) {
                        ForEach(SiteCatalog.all) { item in
                            Label(item.name, systemImage: item.symbol).tag(item)
                        }
                    }
                    .onChange(of: site) { _, newSite in
                        tint = newSite.tint
                        if name.isEmpty { name = newSite.name }
                    }
                    if !site.hint.isEmpty {
                        Text(site.hint).font(.caption).foregroundStyle(.secondary)
                    }
                    if site.id == "custom" {
                        TextField("https://example.com", text: $customURL)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                Section("空间信息") {
                    TextField("名称（如：工作号）", text: $name)
                    ColorRow(selection: $tint)
                }
                Section {
                    Text("创建后系统会为这个空间分配一份独立的网站数据仓库，重启 App 后登录状态依然保留。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("新建空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        let finalName = name.trimmingCharacters(in: .whitespaces).isEmpty ? site.name : name
                        spaceStore.add(name: finalName, site: site, customURL: customURL)
                        dismiss()
                    }
                    .disabled(site.id == "custom" && !isValidURL(customURL))
                }
            }
            .onAppear {
                tint = site.tint
                name = site.name
            }
        }
    }
}

struct EditSpaceView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var spaceStore: SpaceStore
    let space: Space
    @State private var name: String
    @State private var url: String
    @State private var tint: String

    init(space: Space) {
        self.space = space
        _name = State(initialValue: space.name)
        _url = State(initialValue: space.urlString)
        _tint = State(initialValue: space.tint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    ColorRow(selection: $tint)
                }
                Section("起始网址") {
                    TextField("https://", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("仅修改打开时的首页，不影响已有的登录状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("独立数据") {
                    LabeledContent("数据仓库 ID", value: String(space.storeID.uuidString.prefix(8)))
                        .font(.caption)
                }
            }
            .navigationTitle("编辑空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var updated = space
                        updated.name = name
                        updated.urlString = normalizedURL(url)
                        updated.tint = tint
                        spaceStore.update(updated)
                        dismiss()
                    }
                    .disabled(!isValidURL(url))
                }
            }
        }
    }
}

private struct ColorRow: View {
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 12) {
            ForEach(palette, id: \.self) { hex in
                Button {
                    selection = hex
                } label: {
                    ZStack {
                        Circle().fill(Color(hex: hex)).frame(width: 28, height: 28)
                        if selection == hex {
                            Image(systemName: "checkmark")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

func isValidURL(_ text: String) -> Bool {
    guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
          scheme == "https" || scheme == "http", url.host != nil else { return false }
    return true
}

func normalizedURL(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.contains("://") { return trimmed }
    return "https://" + trimmed
}

// MARK: - 锁屏

struct LockOverlay: View {
    @EnvironmentObject private var lock: AppLock
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "lock.shield.fill").font(.system(size: 56)).foregroundStyle(.tint)
                Text("MultiSpace 已锁定").font(.title2.weight(.semibold))
                Button("解锁") { lock.unlock() }.buttonStyle(.borderedProminent)
            }
        }
        .transition(.opacity)
    }
}
