import SwiftUI
import AppCore

@main
struct AgentKeeperApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView(store: store)
                .frame(minWidth: 960, minHeight: 600)
        }
        MenuBarExtra("AgentKeeper", systemImage: "sparkle.magnifyingglass") {
            Button("打开主窗口") {}
            Divider()
            Toggle("摘要面板（占位）", isOn: .constant(false))
        }
    }
}
