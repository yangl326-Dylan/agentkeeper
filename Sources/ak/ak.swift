import AppCore
import Foundation

// ak CLI 入口：参数解析/输出全部收敛在 AppCore.AKCLI（可测），此处只做进程壳。
// @main（而非 main.swift 顶层代码）：universal 双架构 release 构建的编译
// 模式下顶层 await 表达式不被允许（曾用顶层代码，GitHub runner swiftc 拒编译）。
@main
struct AKMain {
    static func main() async throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let result = await AKCLI.run(Array(CommandLine.arguments.dropFirst()), homeDirectory: home)
        print(result.output)
        exit(result.exitCode)
    }
}
