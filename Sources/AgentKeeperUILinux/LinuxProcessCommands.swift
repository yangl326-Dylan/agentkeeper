#if os(Linux)
import Foundation

/// Linux 外部命令的参数组装与输出解析（纯函数，单测覆盖——
/// LinuxPlatformAdapter 只负责进程执行，组装/解析逻辑在此保持可测）。
/// （macOS 对应：MacPlatformAdapter 的 NSWorkspace 调用，无命令行组装。）
public enum LinuxProcessCommands {
    // MARK: xdg-open

    /// xdg-open 可执行名。
    public static let xdgOpenExecutable = "xdg-open"

    /// 用系统默认方式打开 URL（文件/目录/http 均适用）。
    public static func xdgOpenArguments(_ url: URL) -> [String] {
        [url.absoluteString]
    }

    /// 在文件管理器中定位：Linux 无「定位选中」语义 → 打开所在目录
    /// （目标本身是目录则直接打开它）。
    public static func revealArguments(_ url: URL) -> [String] {
        let path = url.path
        let directory: URL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            directory = isDirectory.boolValue ? url : url.deletingLastPathComponent()
        } else {
            directory = url.deletingLastPathComponent()
        }
        return [directory.absoluteString]
    }

    // MARK: zenity 目录选择

    /// zenity 可执行名。
    public static let zenityExecutable = "zenity"

    /// 目录选择器参数（zenity --file-selection --directory；用户取消退出码非 0）。
    public static func zenityDirectoryArguments() -> [String] {
        ["--file-selection", "--directory"]
    }

    /// 解析 zenity 标准输出（单行绝对路径；空/非绝对路径 → nil）。
    public static func parseZenityPath(output: String) -> String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else { return nil }
        return trimmed
    }

    // MARK: gsettings 减少动效探测

    /// gsettings 可执行名。
    public static let gsettingsExecutable = "gsettings"

    /// 读取 GNOME 动效开关（org.gnome.desktop.interface enable-animations）。
    public static func gsettingsReadArguments() -> [String] {
        ["get", "org.gnome.desktop.interface", "enable-animations"]
    }

    /// 解析 gsettings 输出（"true" → 开启动画即未开启减少动效；
    /// 其余任何输出/空输出/命令失败 → 视为「减少动效」不适用，保守返回 false）。
    public static func parseEnableAnimations(output: String) -> Bool {
        output.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }
}

/// 进程执行（薄壳：stdout 捕获；失败返回 nil。仅用于 gsettings/zenity 这类
/// 短生命周期命令；xdg-open 为即发即弃不走本通道）。
enum LinuxProcessRunner {
    /// 候选可执行目录（发行版差异：xdg-open 可能落 /usr/local/bin）。
    private static let searchDirectories = ["/usr/bin", "/usr/local/bin", "/bin"]

    /// 解析可执行绝对路径；找不到返回 nil。
    static func resolveExecutable(_ name: String) -> String? {
        for directory in searchDirectories {
            let candidate = directory + "/" + name
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    /// 同步执行并捕获 stdout（用于 zenity/gsettings；调用方负责后台化）。
    static func output(executable: String, arguments: [String]) -> String? {
        guard let executablePath = resolveExecutable(executable) else { return nil }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 即发即弃（xdg-open：打开器自持生命周期，不等待）。
    static func launch(executable: String, arguments: [String]) {
        guard let executablePath = resolveExecutable(executable) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
#endif
