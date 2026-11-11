import Foundation
import SwiftUI
import Combine
import WebKit
import Security
import LocalAuthentication

// MARK: - Keychain（只存密码，条目元数据走 UserDefaults）

enum KeychainError: LocalizedError {
    case status(OSStatus)
    var errorDescription: String? {
        switch self {
        case .status(let code): return "钥匙串操作失败（OSStatus \(code)）"
        }
    }
}

enum Keychain {
    private static let service = "com.niubige.MultiSpace.vault"

    private static func query(_ account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    @discardableResult
    static func set(_ password: String, for account: String) throws {
        var q = query(account)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        q[kSecValueData as String] = Data(password.utf8)
        SecItemDelete(query(account) as CFDictionary)
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}

// MARK: - WKWebsiteDataStore 对象缓存
// 同一个 UUID 每次调用 init(forIdentifier:) 都会产生一个新对象；
// 不同对象虽然指向同一份磁盘数据，却会失去 WebKit 进程共享，因此必须缓存复用。

final class DataStoreCache {
    static let shared = DataStoreCache()
    private var cache: [UUID: WKWebsiteDataStore] = [:]
    private let lock = NSLock()

    private init() {}

    func store(for id: UUID) -> WKWebsiteDataStore {
        lock.lock()
        defer { lock.unlock() }
        if let existing = cache[id] { return existing }
        let created = WKWebsiteDataStore(forIdentifier: id)
        cache[id] = created
        return created
    }

    func release(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        cache[id] = nil
    }

    func releaseAll() {
        lock.lock()
        defer { lock.unlock() }
        cache.removeAll()
    }
}

// MARK: - 分身数据

final class SpaceStore: ObservableObject {
    @Published private(set) var spaces: [Space] = []
    private let key = "multispace.spaces.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([Space].self, from: data) {
            spaces = decoded
        }
    }

    func add(name: String, site: Site, customURL: String?) {
        var space = Space(name: name, site: site)
        if site.id == "custom", let url = customURL, !url.isEmpty {
            space.urlString = url
        }
        spaces.append(space)
        persist()
    }

    func update(_ space: Space) {
        guard let idx = spaces.firstIndex(where: { $0.id == space.id }) else { return }
        spaces[idx] = space
        persist()
    }

    /// 调用前请确保对应的 WKWebView 已经销毁，否则 data store 仍被占用，删除会失败。
    func delete(_ space: Space, completion: @escaping (Bool, String?) -> Void) {
        let id = space.storeID
        DataStoreCache.shared.release(id)
        spaces.removeAll { $0.id == space.id }
        persist()
        WKWebsiteDataStore.remove(forIdentifier: id) { error in
            DispatchQueue.main.async {
                if let error = error {
                    completion(false, error.localizedDescription)
                } else {
                    completion(true, nil)
                }
            }
        }
    }

    /// 清空某个分身的 Cookie / localStorage，但保留分身本身（等于退出登录）。
    func resetWebsiteData(for space: Space, completion: @escaping () -> Void) {
        let store = DataStoreCache.shared.store(for: space.storeID)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            DispatchQueue.main.async { completion() }
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(spaces) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - 保险箱数据

final class VaultStore: ObservableObject {
    @Published private(set) var items: [VaultItem] = []
    private let key = "multispace.vault.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([VaultItem].self, from: data) {
            items = decoded
        }
    }

    func password(for id: UUID) -> String? { Keychain.get(id.uuidString) }

    func save(_ item: VaultItem, password: String) throws {
        try Keychain.set(password, for: item.id.uuidString)
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx] = item
        } else {
            items.append(item)
        }
        persist()
    }

    func delete(_ item: VaultItem) {
        Keychain.delete(item.id.uuidString)
        items.removeAll { $0.id == item.id }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - 生物识别

final class AppLock: ObservableObject {
    @Published var isLocked = false
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "multispace.lock.enabled") }
    }

    init() {
        self.enabled = UserDefaults.standard.bool(forKey: "multispace.lock.enabled")
        self.isLocked = self.enabled
    }

    func lockIfNeeded() {
        if enabled { isLocked = true }
    }

    func authenticate(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        context.localizedCancelTitle = "取消"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // 模拟器 / 未设置密码的设备：不把用户锁死
            DispatchQueue.main.async { completion(true) }
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,
                               localizedReason: "解锁 MultiSpace 的账号保险箱") { ok, _ in
            DispatchQueue.main.async { completion(ok) }
        }
    }

    func unlock() {
        authenticate { [weak self] ok in
            if ok { self?.isLocked = false }
        }
    }
}
