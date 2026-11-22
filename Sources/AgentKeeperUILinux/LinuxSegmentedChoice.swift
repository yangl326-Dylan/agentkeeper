#if os(Linux)
import SwiftCrossUI
import AgentKeeperShared

/// 选项包装（分段选择控件用；label 随界面语言在渲染期重建）。
public struct LinuxChoiceOption<Value: Equatable>: Identifiable {
    public let value: Value
    public let label: String

    public var id: String { label }

    public init(value: Value, label: String) {
        self.value = value
        self.label = label
    }
}

/// 分段选择控件（等价 macOS `Picker` 的短选项场景）。
/// Gtk3Backend v0.11 的 `createPicker` 是 fatalError 空缺（官方未实现），
/// 而 GTK3 是 AppIndicator 托盘共存的前提——因此设置页用按钮行等价表达
/// （选项 ≤3 时观感与 macOS 分段 Picker 接近，交互语义一致：点选即写回设置）。
public struct LinuxSegmentedChoice<Value: Equatable>: View {
    public let options: [LinuxChoiceOption<Value>]
    public let selection: Value
    public let onSelect: (Value) -> Void

    public init(
        options: [LinuxChoiceOption<Value>],
        selection: Value,
        onSelect: @escaping (Value) -> Void
    ) {
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    public var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection
                Button(option.label) {
                    onSelect(option.value)
                }
                .buttonStyle(.plain)
                // fixedSize：Gtk3 均分会挤压按钮标签（实测 "English" 被截成 "Engli…"）
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? LinuxPalette.selection : LinuxPalette.subtle)
            }
        }
    }
}
#endif
