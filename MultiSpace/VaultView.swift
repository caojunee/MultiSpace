import SwiftUI
import UIKit

struct VaultView: View {
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var spaceStore: SpaceStore
    @EnvironmentObject private var lock: AppLock

    @State private var showingAdd = false
    @State private var editing: VaultItem?
    @State private var revealed: Set<UUID> = []
    @State private var pendingDelete: VaultItem?

    var body: some View {
        List {
            Section {
                Label("密码保存在系统钥匙串，仅本机可见，不会同步到 iCloud。", systemImage: "lock.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if vault.items.isEmpty {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "key.horizontal").font(.largeTitle).foregroundStyle(.tint)
                        Text("还没有保存账号").font(.headline)
                        Text("把每个空间对应的账号密码记在这里，需要时验证面容 ID 后查看。")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                }
            }
            ForEach(vault.items) { item in
                Section {
                    VaultRow(
                        item: item,
                        spaceName: spaceStore.spaces.first { $0.id == item.spaceID }?.name,
                        revealed: revealed.contains(item.id),
                        password: revealed.contains(item.id) ? (vault.password(for: item.id) ?? "未保存") : nil,
                        onReveal: { reveal(item) },
                        onHide: { revealed.remove(item.id) },
                        onCopy: { UIPasteboard.general.string = vault.password(for: item.id) ?? "" }
                    )
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) { pendingDelete = item } label: {
                            Label("删除", systemImage: "trash")
                        }
                        Button { editing = item } label: {
                            Label("编辑", systemImage: "pencil")
                        }.tint(.indigo)
                    }
                }
            }
        }
        .navigationTitle("账号保险箱")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAdd) { VaultEditView(item: nil) }
        .sheet(item: $editing) { item in VaultEditView(item: item) }
        .alert(item: $pendingDelete) { item in
            Alert(
                title: Text("删除「\(item.title)」？"),
                message: Text("账号与密码会被一并移除。"),
                primaryButton: .destructive(Text("删除")) { vault.delete(item) },
                secondaryButton: .cancel()
            )
        }
    }

    private func reveal(_ item: VaultItem) {
        lock.authenticate { ok in
            if ok { revealed.insert(item.id) }
        }
    }
}

private struct VaultRow: View {
    let item: VaultItem
    let spaceName: String?
    let revealed: Bool
    let password: String?
    let onReveal: () -> Void
    let onHide: () -> Void
    let onCopy: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.title).font(.headline)
                Spacer()
                if let spaceName = spaceName {
                    Text(spaceName).font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            Text(item.username).font(.subheadline).foregroundStyle(.secondary)
            if !item.note.isEmpty {
                Text(item.note).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if revealed {
                    Text(password ?? "").font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button { onCopy() } label: { Image(systemName: "doc.on.doc") }
                    Button { onHide() } label: { Image(systemName: "eye.slash") }
                } else {
                    Button { onReveal() } label: {
                        Label("验证并查看密码", systemImage: "faceid").font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

struct VaultEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var vault: VaultStore
    @EnvironmentObject private var spaceStore: SpaceStore

    let original: VaultItem?

    @State private var title = ""
    @State private var username = ""
    @State private var password = ""
    @State private var note = ""
    @State private var spaceKey = ""
    @State private var errorMessage: String?

    init(item: VaultItem?) { self.original = item }

    var body: some View {
        NavigationStack {
            Form {
                Section("账号信息") {
                    TextField("名称（如：小红书工作号）", text: $title)
                    TextField("用户名 / 手机 / 邮箱", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    SecureField("密码", text: $password)
                    Text("写入系统钥匙串，属性为 WhenUnlockedThisDeviceOnly。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("密码")
                }
                Section("备注") {
                    TextEditor(text: $note).frame(minHeight: 72)
                }
                Section("关联空间（可选）") {
                    Picker("关联空间", selection: $spaceKey) {
                        Text("不关联").tag("")
                        ForEach(spaceStore.spaces) { space in
                            Text(space.name).tag(space.id.uuidString)
                        }
                    }
                }
                if let errorMessage = errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle(original == nil ? "新增账号" : "编辑账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let o = original else { return }
                title = o.title
                username = o.username
                note = o.note
                spaceKey = o.spaceID?.uuidString ?? ""
                password = vault.password(for: o.id) ?? ""
            }
        }
    }

    private func save() {
        let item = VaultItem(
            id: original?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            username: username,
            note: note,
            spaceID: UUID(uuidString: spaceKey)
        )
        do {
            try vault.save(item, password: password)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
