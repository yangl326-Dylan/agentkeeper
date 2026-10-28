import SwiftUI
import AppCore
import DomainKit

@main
struct AgentKeeperApp: App {
    @State private var env = AppEnvironment()
    @State private var showOnboarding = true

    var body: some Scene {
        // 单例窗口：MenuBarExtra「打开主窗口」复用已有窗口，而不是新建多个。
        Window("AgentKeeper", id: "main") {
            Group {
                if showOnboarding {
                    OnboardingView(hasCompleted: onboardingBinding)
                } else {
                    RootView()
                }
            }
            .environment(env)
            .frame(minWidth: 1000, minHeight: 640)
            .task {
                await env.bootstrap()
            }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("立即扫描") {
                    Task { await env.scanNow() }
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(env.store.state.scan.phase == .running)
            }
        }

        MenuBarExtra("AgentKeeper", systemImage: "sparkle.magnifyingglass") {
            MenuSummarySection(env: env)
        }
    }

    private var onboardingBinding: Binding<Bool> {
        Binding(
            get: { showOnboarding },
            set: { newValue in
                showOnboarding = newValue
            }
        )
    }
}

struct MenuSummarySection: View {
    let env: AppEnvironment
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let summary = MenuBarSummary.build(
            state: env.store.state,
            skills: env.catalogStore.current
        )
        // 摘要：agent 列表 + 各自 skill 数
        Section {
            ForEach(summary.agentEntries) { entry in
                HStack {
                    Image(systemName: entry.installed ? "checkmark.circle.fill" : "circle.slash")
                        .foregroundStyle(entry.installed ? Color.green : Color.secondary)
                    Text(entry.name)
                    Spacer()
                    Text("\(entry.skillCount) skills")
                        .foregroundStyle(.secondary)
                }
            }
            if summary.agentEntries.isEmpty {
                Text(env.store.state.scan.phase == .running ? "正在扫描…" : "尚未扫描")
                    .foregroundStyle(.secondary)
            }
            Divider()
            Text("Skill 总量 \(summary.totalSkills)")
                .font(.callout)
        }
        Divider()
        Button("打开主窗口") {
            NSApplication.shared.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Button {
            Task {
                NSApplication.shared.activate(ignoringOtherApps: true)
                await env.scanNow()
            }
        } label: {
            if env.store.state.scan.phase == .running {
                HStack { Text("正在扫描…"); Spacer(); ProgressView().controlSize(.small) }
            } else {
                HStack { Text("立即扫描"); Spacer(); Image(systemName: "arrow.clockwise") }
            }
        }
        .disabled(env.store.state.scan.phase == .running)
        Divider()
        Button("退出 AgentKeeper") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
