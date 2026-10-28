# Tasks

## 1. 准备与契约
- [ ] 1.1 在 DomainKit 新增分领域模型：`DistributionSource`（existingSkill / localDirectory / git）、`DistributionConflict`（targetPath/mine/theirs 指纹）、`InstallPlan`、`LandingPoint`；RED 先写 `Tests/DomainKitTests/DistributionModelTests.swift` 验证编码与哈希稳定。
- [ ] 1.2 定义 `AppCore` 侧分发协议（`Distributing` 接口）与错误类型（conflict/invalidSource/cloneFailed/timeout），RED：协议契约测试（非法参数返回错误而非崩溃）。

## 2. git 来源与临时区
- [ ] 2.1 `InfraKit.GitInstaller`：`clone(url:)` 走 `git clone --depth 1`，本地路径（存在目录）直接返回该 URL 不 clone；RED：本地路径返回原目录、伪造 git URL 返回 cloneFailed。
- [ ] 2.2 clone 超时 60s 与 stderr 摘要透传；失败清理 `~/.agentkeeper/tmp/clone-<uuid>/`；RED：无法访问 URL → 失败 + 临时目录不存在。
- [ ] 2.3 候选发现：仓库根合法 → 单候选；否则一级子目录逐个用 SkillParsing 校验；RED：单 skill 仓库 / 多 skill 仓库 / 空仓库三 fixture。
- [ ] 2.4 提交 group 2，tick 2.1–2.3。

## 3. SkillDistributor 安装管线
- [ ] 3.1 `InfraKit.SkillDistributor.install(source:.existingSkill)`：复制到目标 skillRoot（AtomicMover 复制路径），来源不变；RED：装后源目录内容不变、目标出现且指纹一致。
- [ ] 3.2 冲突检查：目标存在且指纹不一致 → 中止 + `DistributionConflict` 明细，零写入；一致 → 报告已铺设跳过；RED：三 fixture（空目标/一致/冲突）。
- [ ] 3.3 接入 localDirectory 来源：校验 SKILL.md + frontmatter，非法 → invalidSource 且缺项说明；RED：合法导入成功、无 SKILL.md 拒绝、坏 frontmatter 拒绝、冲突拒绝四例。
- [ ] 3.4 接入 git 来源：2.3 候选 × 3.1/3.2 管线，多候选逐个安装；RED：git 安装成功后临时区清空、目标重扫可见。
- [ ] 3.5 失败回滚审计：安装中断不遗留半成品目标目录；RED：人为注入 copy 失败 → 目标目录不存在。
- [ ] 3.6 提交 group 3，tick 3.1–3.5。

## 4. 铺设落点与更新所有落点
- [ ] 4.1 `AppCore.CatalogQuery.landingPoints(named:)`：按同名+指纹分组返回 `LandingPoint` 清单；RED：两 agent 同名同指纹 → 两落点互链；指纹分歧 → 分组拆分。
- [ ] 4.2 `AppCore.SkillDistributor.updateAllLandingPoints(from:)`：每落点先自动快照再覆盖 copy+verify，落点在 disabled 区则跳过并列出；RED：更新后各落点指纹一致、disabled 落点未被触碰、每落点新增快照。
- [ ] 4.3 逐落点回滚：任一落点覆盖失败 → 该落点恢复原状，其余已完成落点保持（并报告部分成功明细）；RED：注入失败 fixture。
- [ ] 4.4 提交 group 4，tick 4.1–4.3。

## 5. TagStore 与 TagService
- [ ] 5.1 `InfraKit.TagStore`：`~/.agentkeeper/tags.json` 读写（原子写 + rename）；RED：写后重读一致、损坏 JSON → 备份 `.corrupt-<ts>` 并空库自愈。
- [ ] 5.2 关联 key 用 skillID（禁用/启用后不变）；RED：禁用→启用循环后 assignment 保留。
- [ ] 5.3 `AppCore.TagService`：标签增删/重命名（同步全部关联）、按 skillID 增删；RED：重命名后关联全部更新、删除标签不动 skill 文件。
- [ ] 5.4 orphan 检测：重扫钩子对照 catalog，缺失且非 disabled 的 skillID 计入 orphanCount，一键清除；RED：删除 skill 目录后 orphan 计数 +1，清除后归零。
- [ ] 5.5 提交 group 5，tick 5.1–5.4。

## 6. AppCore 操作编排
- [ ] 6.1 `AppCore.DistributionService`：接入 OperationService 状态机（install/import/gitClone 走 started→completed→自动重扫；失败不重扫）；RED：成功后 catalog 自动刷新、失败 catalog 不动 + OperationHistory 有记录。
- [ ] 6.2 分发操作串行化：同一时刻最多一个分发任务；RED：并发两次安装按序完成且无交错写入。
- [ ] 6.3 `CatalogQuery` 增加标签筛选维度（tagFilter 参数）与标签分组枚举；RED：按标签筛选结果正确、禁用条目带标记出现。
- [ ] 6.4 提交 group 6，tick 6.1–6.3。

## 7. UI 集成
- [ ] 7.1 详情页「安装到其他 agent…」入口 + agent/skillRoot 选择弹窗 + 冲突面板（复用 RemediationPresentation）；手工走查脚本记录。
- [ ] 7.2 工具栏「导入 skill…」（目录选择 NSOpenPanel）与「从 git 安装…」（URL 表单 + 多候选勾选面板 + 失败原因展示）。
- [ ] 7.3 详情页铺设落点面板：落点清单、分歧标记、「以此版本更新所有落点…」确认框（列明将写落点）。
- [ ] 7.4 标签 UI：详情页 chips 编辑 + 输入补全；导航树「标签」分组；筛选器标签维度。
- [ ] 7.5 全部新操作接入 StatusSemantics/MotionPolicy（含「减少动态效果」降级）；错误的非阻断呈现。
- [ ] 7.6 `swift build` 零警告提交；提交 group 7，tick 7.1–7.5。

## 8. 验收与收尾
- [ ] 8.1 自动化 E2E：`DistributionE2EWorkflowTests`：git 安装 → 跨 agent 安装 → 铺设互链 → 外部改一处落点 → 分歧提示 → updateAllLandingPoints → 快照历史与前次一致；RED 先行。
- [ ] 8.2 性能：200 skill 目录下 100 次标签写 <2s；双 agent × 50 skill 铺设分组计算 <1s；RED 先行。
- [ ] 8.3 边界演练：tags.json 损坏的 E2E 不影响扫描/分发；clone 超时不阻塞 UI；RED 先行。
- [ ] 8.4 全量 `swift test --filter` 三连绿 + 完整 suite ×2 绿；`openspec validate add-skill-distribution` 通过。
- [ ] 8.5 最终提交 + tasks.md 全部 tick。
