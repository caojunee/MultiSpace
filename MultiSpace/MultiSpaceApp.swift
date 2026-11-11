import SwiftUI

@main
struct MultiSpaceApp: App {
    @StateObject private var spaceStore = SpaceStore()
    @StateObject private var vault = VaultStore()
    @StateObject private var lock = AppLock()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(spaceStore)
                .environmentObject(vault)
                .environmentObject(lock)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        lock.lockIfNeeded()
                    case .active:
                        if lock.isLocked { lock.unlock() }
                    default:
                        break
                    }
                }
        }
    }
}
