import Foundation

/// AppCore 测试专用"家目录"夹具（与 InfraKitTests 同形）。
@discardableResult
func makeFakeHome(
    files: [String],
    fileContents: [String: String] = [:]
) -> URL {
    let home = FileManager.default.temporaryDirectory
        .appendingPathComponent("ak-core-fixture-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    for relative in files {
        let target = home.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        let content = fileContents[relative] ?? "placeholder\n"
        try? content.write(to: target, atomically: true, encoding: .utf8)
    }
    return home
}

func cleanup(_ home: URL) {
    try? FileManager.default.removeItem(at: home)
}
