# skill-snapshots Specification

## Purpose

为 skill 内容建立本地自动快照与历史视图：AgentKeeper 自行备份每次变更并支持查看与恢复；对来源于 git 仓库的 skill，同时读取并展示其 git 历史。该能力保证任何误改都可回溯。

## Requirements

### Requirement: 自动快照
系统 SHALL 在检测到 skill 内容指纹变化时自动创建快照（manifest + 文件副本，含 SHA256），存储于 AgentKeeper 应用数据目录；连续无变更的间隔期 MUST NOT 产生重复快照（按指纹去重）。

#### Scenario: 修改产生快照
- **WHEN** 某 skill 的内容文件被修改且指纹变化
- **THEN** 系统自动保存一份变更后的快照，历史列表新增一条带时间戳的记录

#### Scenario: 重复内容不重复快照
- **WHEN** 修改将文件改回与之前快照一致的内容
- **THEN** 不产生新的快照记录（指纹去重），历史上保留空白间隔

### Requirement: 历史查看与 diff
用户 SHALL 能查看某个 skill 的快照历史列表，并查看任意两个版本之间的差异视图；快照数量超过保留上限时系统 MUST 按最旧优先策略淘汰。

#### Scenario: 查看历史列表
- **WHEN** 用户进入某 skill 的历史版本面板
- **THEN** 看到按时间倒序的快照列表，包含时间戳与变更文件数

#### Scenario: 查看版本差异
- **WHEN** 用户选中两个历史版本（或工作区与某版本）进行比较
- **THEN** 界面展示逐文件的 diff 视图，区分新增/修改/删除

### Requirement: 恢复旧版本
用户 SHALL 能将当前工作区 skill 内容恢复为某个历史快照；恢复操作 MUST 先对当前状态自动另存一份快照，再执行恢复，且恢复过程符合文件操作原子性要求。

#### Scenario: 成功恢复
- **WHEN** 用户选择某个历史快照并点击恢复
- **THEN** 当前状态先被快照，随后 skill 内容回到所选版本，agent 下次读取时得到旧版本内容

### Requirement: Git 历史读取
当 skill 目录位于 git 仓库内时，系统 SHALL 读取该 skill 路径的 git 提交历史并展示（时间、作者、摘要），并 SHALL 能查看任意提交与工作区之间的 diff。

#### Scenario: git 来源 skill 展示提交历史
- **WHEN** 某 skill 所在目录属于一个 git 仓库且含提交
- **THEN** 历史面板在本地快照之外展示该 skill 路径的提交历史

#### Scenario: 非 git 目录不误导
- **WHEN** 某 skill 目录不在任何 git 仓库内
- **THEN** 历史面板只显示本地快照，不显示错误或不存在的 git 数据

### Requirement: 快照安全
快照操作 SHALL 是只读式备份：快照过程 MUST NOT 修改 skill 工作区文件；快照存储损坏或快照缺失 MUST NOT 影响扫描与管理功能。

#### Scenario: 快照存储损坏不影响主流程
- **WHEN** 快照存储目录被外部意外破坏
- **THEN** 扫描、查看、启用/禁用功能照常工作，历史面板给出快照不可用的明确提示
