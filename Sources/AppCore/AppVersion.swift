import Foundation

/// 语义化版本（数字段比较；容忍 `v` 前缀、位数差异与预发布/构建后缀）。
///
/// 归一化规则：去掉尾部 0，因此 `1.2` 与 `1.2.0` 相等。
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// 归一化后的数字段（至少一段）。
    public let components: [Int]

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }
        // 预发布 / 构建元数据不参与比较
        if let suffixStart = text.firstIndex(where: { $0 == "-" || $0 == "+" }) {
            text = String(text[..<suffixStart])
        }
        guard !text.isEmpty else { return nil }

        var parsed: [Int] = []
        for part in text.split(separator: ".", omittingEmptySubsequences: false) {
            guard !part.isEmpty,
                  part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(part)
            else { return nil }
            parsed.append(number)
        }
        guard !parsed.isEmpty else { return nil }
        while parsed.count > 1, parsed.last == 0 {
            parsed.removeLast()
        }
        self.components = parsed
    }

    /// 当前 App 的 `CFBundleShortVersionString`；非 App Bundle（如 `swift run`）回退 0.0.0。
    public static var currentBundleVersion: AppVersion {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return AppVersion(raw ?? "") ?? AppVersion("0.0.0")!
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }
}
