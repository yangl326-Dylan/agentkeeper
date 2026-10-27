# Tasks

## 1. 工程骨架与架构分层

- [x] 1.1 创建 Swift Package / Xcode 项目骨架：`AgentKeeper`（App target, SwiftUI App 生命周期, MenuBarExtra 入口）、`DomainKit`、`AppCore`、`InfraKit` target；组建 Product 多 target 结构；App 可空跑启动并显示占位三面板窗口；验证：`swift build` 通过、模拟器运行出现占位窗口
- [x] 1.2 定义 DomainKit 核心模型与协议：`Agent`/`AgentInstallState`/`SkillRoot`/`ProjectRoot`/`Skill`/`SkillScope(.global/.agentOnly/.project/.multiAgent)`/`SkillStatus`/`ScanReport`/`ParsedSkill`，及 `AgentAdapter`、`FileMonitoring`（协议）等接口；项目标签由项目根派生校验逻辑入模型；验证：模型层单测（编码、作用域枚举语义）通过
- [x] 1.3 建立 AppCore 的 `AppUpdate` 消息流与 reducer 状态骨架（AppState: scanState/catalog/filters/uiState）；验证：reducer 纯函数单测（初始状态、示例 action 推进）通过
- [x] 1.4 Presentation 占位接线：三面板空视图 + AppUpdate 订阅渲染的 harness；验证：向消息流注入测试 action，视图状态变化可观测（Preview/截图或 UI 冒烟）

## 2. Agent 发现（agent-discovery）

- [x] 2.1 实现 Claude Code adapter：`~/.claude/` 检测 + 用户级 `~/.claude/skills` root + 从 Claude 配置读取 projects 记录作为项目根 + 结构版本声明与 `.unrecognized` 降级；验证：fixture 目录（真实 ~/.claude 结构快照）单测——安装/未安装/结构未知/项目根提取四态
- [x] 2.2 实现 OpenCode 与 Codex CLI adapter：安装检测 + 用户级 skill root + 结构版本声明与 `.unrecognized` 降级（OpenCode 本身即本项目运行环境,目录结构可直接实测采样）；验证：两 adapter 的 fixture 单测通过
- [x] 2.3 实现 Gemini CLI、OpenClaw adapter：安装检测 + 各自 skill 目录定位（OpenClaw workspace/skills 结构,以实施时实测为准采样 fixture）+ 降级路径；验证：fixture 单测通过
- [x] 2.4 实现 pi/oh-my-pi adapter（单 adapter 双识别）：检测 pi 与 oh-my-pi 各自配置与 skill 目录、互不串扰、共同结构规则复用；验证：pi 环境 fixture 单测双实例识别
- [x] 2.5 实现 AgentRegistry + 扫描调度器：遍历注册表、多 adapter 并发扫描、产出 `ScanReport`（含性能诊断）；验证：含 4+ fake adapter 的注册表单测与扫描进度发布测
- [x] 2.6 项目根发现与扫描范围管理：adapter `discoverProjectRoots()` 流程、用户增删项目根设置项、范围变更触发重扫；验证：无项目根记录 adapter 的「仅用户添加」行为单测 + 范围设置集成测
- [x] 2.7 权限不足与只读异常路径处理：失败报告结构（目录+原因+授权引导 key）；验证：无权限目录 fixture 单测
- [x] 2.8 AppCore 接线扫描 action：后台队列执行、扫描状态机（idle/running/complete/failed）、进度注入 `AppUpdate`；验证：reducer 状态机单测 + fake scanner 端到端

## 3. Skill 目录与索引（skill-catalog）

- [x] 3.1 实现 SKILL.md 探测与 frontmatter 解析（name/description），含递归遍历与 skip 规则；验证：典型/缺失字段的 fixture 解析单测
- [x] 3.2 实现 SHA256 内容指纹（覆盖 SKILL.md+随附脚本），含大文件流式处理；验证：指纹向量单测、同内容不同路径指纹一致
- [x] 3.3 实现作用域判定：私有目录→专属；共享引用目录→全局；项目根内→项目级（自动项目标签）；同名同指纹多目录→multi-agent 铺设（含判定原因透出）；验证：四种作用域 fixture 单测
- [x] 3.4 实现 SkillIndex（SQLite）：建表、增量 upsert、全量 rebuild、integrity check 失败自动重建；验证：索引 CRUD/rebuild/损坏恢复单测
- [x] 3.5 实现 FileMonitor（FSEvents）：per-root 监听、500ms debounce 聚合、增量重扫触发、FakeMonitor 注入协议；验证：真实 FSEvents 集成测（临时目录写入触发）+ 协议级单测
- [x] 3.6 实现 catalog snapshot 内存视图与统一查询（agent/作用域/名称筛选、搜索）；验证：查询组合单测；索引失真时以磁盘纠正的行为测
- [x] 3.7 AppCore 接线：外部变更→增量扫描→catalog 更新→UI 刷新链路；验证：临时目录中改文件、catalog 数秒内更新的集成测

## 4. Skill 生命周期操作（skill-lifecycle）

- [x] 4.1 实现原子搬移 Primitive：同卷 rename、跨卷 copy+verify+delete、失败回滚引擎（基于 manifest 步骤栈）；验证：临时目录搬移/中断注入/回滚单测
- [ ] 4.2 实现禁用流程：搬移至 `~/.agentkeeper/disabled/<agent>/<skill>`、manifest 写入、冲突检测（目标/回原路径被占即中止）；验证：禁用/恢复/冲突三场景集成测
- [ ] 4.3 实现恢复启用流程：按 manifest 回原路径、原路径冲突中止并输出冲突明细、manifest 清理；验证：含冲突 fixture 的集成测
- [ ] 4.4 操作历史记录器（时间/skill/方向/结果）与查询接口；验证：增删查单测
- [ ] 4.5 删除确认流程：删除类操作统一确认入口（路径清单+确认回调）；验证：确认/取消两路径行为测
- [ ] 4.6 AppCore 操作状态机接线（操作进行中/完成后 catalog 即时更新 + AppUpdate 广播）；验证：fake lifecycle 端到端状态流测

## 5. 快照与历史（skill-snapshots）

- [ ] 5.1 实现 SnapshotStore：指纹变化触发快照、目录形态存储、指纹去重、50 份最旧淘汰（可配置）；验证：触发/去重/淘汰单测
- [ ] 5.2 实现快照历史查询与两版本 diff 数据生成（逐文件 diff、新增/修改/删除分类）；验证：快照/对比/diff fixture 单测
- [ ] 5.3 实现恢复旧版本流程（先快照当前→重建旧内容），并接入 4.1 原子引擎；验证：恢复集成测（数据校验逐字节一致）
- [ ] 5.4 实现 GitService：`git log --porcelain` / `git diff` CLI 封装、版本嗅探、非 git 目录返回空集不报错；验证：真实临时 git 仓库 fixture 单测 + 非 git 目录幂等测
- [ ] 5.5 AppCore 接线：自动快照联动指纹更新、历史查询 action、恢复 action；验证：mock store 状态流测

## 6. UI 壳（app-ui）

- [ ] 6.1 实现导航树（全局 / agent 专属 / 项目三类组织，项目级自动按项目名分组，分组计数）、列表（筛选/搜索交互）与详情面板（SKILL.md AttributedString 渲染、文件清单、历史入口）的完整三面板；验证：真机/截图走查 + 交互冒烟
- [ ] 6.2 实现状态语义系统：状态→颜色/图标映射、悬停释义、Reduce Motion 降级；验证：语义映射单测 + 辅助功能开关行为验证
- [ ] 6.3 实现扫描进度动效与列表/详情过渡动效（spring/snappy、非阻塞指示）；验证：动效 onset/off 可观测、Reduce Motion 下即时切换
- [ ] 6.4 实现 MenuBarExtra：agent 摘要、skill 数量、打开主窗口、立即扫描入口；验证：菜单行为测 + 与主窗口扫描 action 打通
- [ ] 6.5 实现错误呈现系统：内联提示、状态标记、修复引导跳转、非阻断通知；验证：权限失败场景 UI 行为测
- [ ] 6.6 首启引导页（扫描说明、目录授权、`~/.agentkeeper` 说明）；验证：首启流程走查

## 7. 集成验证与稳定化

- [ ] 7.1 真机 E2E 手动验收：本机已安装的全部 agent（Claude Code/Codex/Gemini/OpenCode/OpenClaw/pi 中实际存在者）全流程（扫描→浏览→筛选→禁用→恢复→修改触发快照→diff→恢复旧版本→菜单栏操作→项目级分组浏览）；验证：验收清单全项通过并记录
- [ ] 7.2 性能与稳定性压测：200+ skill 目录扫描耗时、FSEvents 事件风暴（脚本批量写文件）下字典/CPU 表现、索引重建体验；验证：性能报告达标（扫描 < 2s @ 200 skills 量级、批量事件 UI 无卡顿）
- [ ] 7.3 崩溃与损坏恢复演练：手删 `~/.agentkeeper` 子树、损坏 SQLite、中断搬移（kill -9）后重启的行为；验证：各场景 UI 可用、数据零丢失
- [ ] 7.4 Swift 6 并发审计与警告清零（strict concurrency 下无 warning）；验证：`swift build` 警告 0
