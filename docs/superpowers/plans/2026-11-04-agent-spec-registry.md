# 实施计划：AgentSpec 单源注册表 + 用户自定义 agent

日期：2026-11-04
设计：`docs/superpowers/specs/2026-11-04-agent-spec-registry-design.md`

## 步骤（TDD，每步先红后绿）

1. **AgentSpec 测试**（`Tests/InfraKitTests/AgentSpecTests.swift`）
   - 10 个内置 id 唯一且齐全
   - claude-code：`.claude.json` 项目根发现；opencode：2 条 glob
   - 项目布局派生：claude/opencode/codex/gemini 非空，pi/oh-my-pi/openclaw 为空
2. **AgentSpec 实现**（`Sources/InfraKit/AgentSpec.swift`）
   - `AgentSpec` + `BuiltInAgents`（10 个字面量 + `all` + `spec(for:)`）
   - `ProjectRootDiscovery` 补 `Hashable`
3. **接缝改造**
   - `StandardAgentAdapter.init(spec:homeDirectory:)`；删除 9 个工厂
   - `NamedAdapters` / `ClaudeCodeAdapter` 委托 spec
   - `AgentRegistry`：specs + configDiagnostics；`init(homeDirectory:)` 合并用户 specs
   - `ProjectRootScanner(specs:)`；`ScanScheduler` 传 registry.specs 并附带 configDiagnostics
   - `MenuBarIcons.icon(for:homeDirectory:)` 派生
4. **用户配置测试 → 实现**（`UserAgentConfigLoader`）
   - 合法 / 冲突 / 绝对路径 / `..` / 坏 JSON / 重复 id / 文件缺失
5. **生命周期区目录枚举测试 → 实现**
   - 无 knownAgentIDs 也能看到 qwen 与自定义 agent 的停用/回收站条目
   - 孤儿 manifest 清理不受影响
6. **端到端测试**：fake home + `.windsurf/skills/foo` + agents.json → registry → scheduler → agent installed + skill root
7. **文档**：`docs/adding-an-agent.md`、README `agents.json` 一节、openspec agent-discovery 增补（可选）
8. **验收**：`swift build`（0 warning）、`swift test` 全绿、`ak doctor` 真实机器零回归
9. **提交**：代码 + 测试 + 文档一笔

## 风险与缓解

- `ProjectRootScanner` 签名变化影响 `ProjectScopeTests` → 默认参数保持旧调用可用
- `SkillLifecycle` 枚举变化可能暴露历史孤儿目录 → 这是期望行为，UI 会显示可恢复条目
- 用户配置读盘发生在每次扫描/菜单栏渲染 → 单次小 JSON 读取，可接受；不做缓存（避免失效复杂度）
