# Spec Delta

## MODIFIED Requirements

### Requirement: 三面板主窗口
主窗口 SHALL 采用三面板布局：左侧为 agent/skill 导航树（含作用域分组），中部为实体列表（可筛选/搜索），右侧为所选条目详情（含 SKILL.md 渲染、文件列表、历史入口）。布局 SHOULD 遵循所在平台的原生交互习惯（macOS：导航侧栏、可调整分隔、键盘导航；Linux：GNOME/GTK 习惯）。

#### Scenario: 下钻浏览
- **WHEN** 用户在导航树选择某一 agent，再点选列表中的某个 skill
- **THEN** 右侧详情显示该 skill 的元数据、作用域标记与内容预览

#### Scenario: 键盘导航
- **WHEN** 用户在列表中使用键盘上下移动或按下搜索快捷键
- **THEN** 焦点与选中项随之变化，行为与所在平台的系统应用习惯一致

### Requirement: 菜单栏常驻入口
应用 SHALL 在所在平台提供常驻入口：macOS 为菜单栏项（MenuBar Extra），Linux 为系统托盘项（StatusNotifierItem/AppIndicator，桌面不支持时降级为仅主窗口并在界内提示）；入口均 SHALL 展示 agent 安装数量与 skill 总量摘要，并 MUST 提供快速入口（打开主窗口、立即扫描）。

#### Scenario: 状态摘要
- **WHEN** 用户点击所在平台的常驻入口图标
- **THEN** 面板显示已安装 agent 列表（含各自 skill 数量）与整体状态，可点击进入主窗口对应视图

#### Scenario: 快速扫描
- **WHEN** 用户在常驻入口触发「立即扫描」
- **THEN** 与主窗口触发相同的扫描流程，完成后摘要同步更新

### Requirement: 扫描与状态动效
扫描进行中 SHALL 显示可感知的进度反馈（如呼吸态指示、进度条）；列表与详情的状态切换 MUST 使用轻量、克制的过渡动效（淡入淡出/位移），动效时长与 easing MUST 遵循所在平台的原生质感（macOS：AppKit/SwiftUI 质感；Linux：GTK 质感），MUST NOT 使用打扰性动画。

#### Scenario: 扫描动效
- **WHEN** 一次后台扫描正在进行
- **THEN** UI 出现非阻塞的进行中指示，扫描完成时以平滑过渡呈现新结果

#### Scenario: 尊重系统减少动态效果
- **WHEN** 系统开启了「减少动态效果」辅助功能
- **THEN** 应用以近乎即时的切换呈现，保留状态语义但移除装饰性动画
