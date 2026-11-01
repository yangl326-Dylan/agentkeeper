import AppCore
import Foundation

// ak CLI 入口：参数解析/输出全部收敛在 AppCore.AKCLI（可测），此处只做进程壳。
let home = FileManager.default.homeDirectoryForCurrentUser
let result = await AKCLI.run(Array(CommandLine.arguments.dropFirst()), homeDirectory: home)
print(result.output)
exit(result.exitCode)
