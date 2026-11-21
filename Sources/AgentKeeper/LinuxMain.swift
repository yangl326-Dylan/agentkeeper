import Foundation
import AppCore

/// Linux 侧可执行占位入口（Linux GUI 由 openspec change `add-linux-app` 交付后替换为 SCUI App）。
/// os 条件编译纪律允许：本文件为可执行入口。
#if os(Linux)
@main
struct AgentKeeperLinuxMain {
    static func main() {
        print("AgentKeeper Linux GUI 尚未交付（见 openspec/changes/add-linux-app）。请使用 ak CLI。")
        exit(2)
    }
}
#endif
