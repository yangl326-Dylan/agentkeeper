import SwiftUI
import AppKit
import AppCore

/// Finder 风格文件清单：目录/文件图标、层级缩进、点选、双击/菜单在 Finder 定位。
@MainActor
struct FileListView: View {
    let baseDirectory: URL
    let entries: [SkillPreviewModel.FileListEntry]

    @State private var selectedPath: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("文件清单（\(entries.count)）", systemImage: "folder")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(entries, id: \.path) { entry in
                        row(entry)
                    }
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: 320)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(ClaudePalette.card)
            )
        }
    }

    private func row(_ entry: SkillPreviewModel.FileListEntry) -> some View {
        let path = entry.path
        let depth = path.filter { $0 == "/" }.count
        let name = (path as NSString).lastPathComponent
        let url = baseDirectory.appendingPathComponent(path)
        return HStack(spacing: 8) {
            Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                .foregroundStyle(entry.isDirectory ? Color.accentColor.opacity(0.75) : Color.secondary)
                .font(.system(size: 13, weight: .medium))
            Text(name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            // 在 Finder 定位（受托图标 + tooltip；避免 Button 出现在离屏快照的已知坑）
            Image(systemName: "arrow.up.right.square")
                .foregroundStyle(.secondary)
                .font(.callout)
                .help("在 Finder 中显示")
                .onHover { hovering in if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .onTapGesture { reveal(url) }
        }
        .padding(.vertical, 3)
        .padding(.leading, CGFloat(depth) * 16 + 6)
        .padding(.trailing, 8)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(selectedPath == path ? Color.accentColor.opacity(0.16) : .clear)
        )
        // Finder 习惯：单击选中；菜单里给显式入口
        .onTapGesture { selectedPath = path }
        .contextMenu {
            Button("在 Finder 中显示") { reveal(url) }
            if entry.isDirectory {
                Button("打开文件夹") { open(url) }
            }
        }
        .onTapGesture(count: 2) { reveal(url) }
        .help(entry.isDirectory ? "双击打开该文件夹（Finder 定位）" : "双击在 Finder 中显示此文件")
    }

    /// Finder 定位并选中该文件/文件夹。
    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 在 Finder 打开文件夹本身。
    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
