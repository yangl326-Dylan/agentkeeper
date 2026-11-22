# Installation / 安装文档

[English](#english) | [中文](#中文)

Requirements / 系统要求：
- macOS 15+ · Universal binary（Apple Silicon 与 Intel Mac 均可用）
- Linux: Ubuntu 24.04+ · CLI `ak` + GUI `agentkeeper`（GTK3，详见下文）

---

<a id="english"></a>

## English

### Option 1: Human — Download release (recommended)

**CLI `ak` (macOS)**

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

`ak doctor` prints every detected agent's install status and skill count. Exit code is 0 on success, 2 on unknown command.

**CLI `ak` (Linux, Ubuntu 24.04+)**

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-linux-ubuntu24.04.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

> The Linux binary statically links the Swift runtime — no Swift toolchain needed. System deps: glibc and libsqlite3 (preinstalled on Ubuntu 24.04 desktop/server images; `sudo apt-get install -y libsqlite3-0` if missing).

**GUI app (Linux, Ubuntu 24.04+ / GNOME)**

```bash
# .deb（含 GUI + CLI，装到 /usr/bin；system deps 由 apt 自动补齐）
curl -L -o /tmp/agentkeeper.deb https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/agentkeeper_amd64.deb
sudo apt-get install -y /tmp/agentkeeper.deb
agentkeeper   # GUI；CLI 仍可用 ak
```

> GUI deps: `libgtk-3-0`, `libayatana-appindicator3-1`, `libsqlite3-0` (declared in the .deb; preinstalled on Ubuntu 24.04 desktop).
> Tray uses the StatusNotifier/AppIndicator protocol — visible on GNOME (Ubuntu default extension), KDE, and other SNI-capable desktops; on desktops without tray support the app degrades to main-window-only with an in-app notice.
> A portable tar.gz (`agentkeeper-gui-linux-*.tar.gz`) is also published for non-dpkg systems.

**GUI app (macOS)**

```bash
curl -L -o /tmp/ak-app.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-app-macos.zip
unzip -o /tmp/ak-app.zip -d /tmp/ak-app
sudo mv /tmp/ak-app/AgentKeeper.app /Applications/AgentKeeper.app
```

> Build assets are **not notarized yet** (roadmap). If macOS refuses to open the app because it "cannot be verified", run `xattr -cr /Applications/AgentKeeper.app` once, or right-click → Open on first launch. Skip this if it runs fine.

### Option 2: Human — Build from source

```bash
git clone https://github.com/yangl326-Dylan/agentkeeper.git
cd agentkeeper
scripts/build-app.sh release   # → ./AgentKeeper.app
swift build -c release && sudo install -m 0755 .build/release/ak /usr/local/bin/ak
```

Swift 6.0+ required (`swift --version` to check; Xcode or Command Line Tools with Swift 6 toolchain).

> **For AI agents installing on a user's machine:** use the same Option 1 commands. See [AGENTS.md](AGENTS.md) for behavior guidelines (confirm before modifying skill files; `ak list` / `ak doctor` are read-only and always safe).

### Agent install / update

AI agents (Claude Code, OpenCode, Codex, …) can install or update `ak` by running the Option 1 CLI block. The commands are idempotent — re-running them upgrades an existing install. Verify with:

```bash
ak list    # readonly table of every skill, scope, owning agents and paths
```

### Skill distribution

The `agentkeeper` skill ships with this repository: `npx skills add yangl326-Dylan/agentkeeper --skill agentkeeper` (Claude Code / Codex / OpenCode / Cursor / Gemini CLI and more). For harnesses without a registry, copy the file directly: DeepSeek Harness `cp skills/agentkeeper/SKILL.md ~/.dsh/skills/agentkeeper.md`; pi `mkdir -p ~/.pi/skills/agentkeeper && cp skills/agentkeeper/SKILL.md ~/.pi/skills/agentkeeper/`; agents shared dir likewise at `~/.agents/skills/agentkeeper/`.

---

<a id="中文"></a>

## 中文

### 方式一：人类——下载 Release（推荐）

**CLI `ak`（macOS）**

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

`ak doctor` 输出每个 agent 的安装状态与 skill 数；退出码 0 成功、2 未知命令。

**CLI `ak`（Linux，Ubuntu 24.04+）**

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-linux-ubuntu24.04.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

> Linux 二进制静态链接 Swift 运行时——无需安装 Swift 工具链。系统依赖：glibc 与 libsqlite3（Ubuntu 24.04 桌面/服务器镜像自带；缺失时 `sudo apt-get install -y libsqlite3-0`）。

**GUI App（Linux，Ubuntu 24.04+ / GNOME）**

```bash
# .deb（含 GUI + CLI，装到 /usr/bin；系统依赖由 apt 自动补齐）
curl -L -o /tmp/agentkeeper.deb https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/agentkeeper_amd64.deb
sudo apt-get install -y /tmp/agentkeeper.deb
agentkeeper   # GUI；CLI 依旧可用 ak
```

> GUI 依赖：`libgtk-3-0`、`libayatana-appindicator3-1`、`libsqlite3-0`（.deb 已声明；Ubuntu 24.04 桌面版自带）。
> 托盘走 StatusNotifier/AppIndicator 协议——GNOME（Ubuntu 默认扩展）、KDE 等 SNI 桌面可见；无托盘支持的桌面自动降级为仅主窗口 + 界内提示。
> 非 dpkg 系统可发布目录中的便携 tar.gz（`agentkeeper-gui-linux-*.tar.gz`）。

**GUI App（macOS）**

```bash
curl -L -o /tmp/ak-app.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-app-macos.zip
unzip -o /tmp/ak-app.zip -d /tmp/ak-app
sudo mv /tmp/ak-app/AgentKeeper.app /Applications/AgentKeeper.app
```

> Release 产物**暂未公证**（见 roadmap）。若 macOS 提示「无法验证开发者」，执行一次 `xattr -cr /Applications/AgentKeeper.app`，或首次右键 → 打开。能正常打开则无需处理。

### 方式二：人类——从源码构建

```bash
git clone https://github.com/yangl326-Dylan/agentkeeper.git
cd agentkeeper
scripts/build-app.sh release   # → 产出 ./AgentKeeper.app
swift build -c release && sudo install -m 0755 .build/release/ak /usr/local/bin/ak
```

需要 Swift 6.0+（用 `swift --version` 检查；需带 Swift 6 工具链的 Xcode 或 Command Line Tools）。

> **给在用户机器上安装的 AI agent**：直接用方式一的 CLI 命令块。行为规范见 [AGENTS.md](AGENTS.md)（修改 skill 文件前先向用户确认；`ak list` / `ak doctor` 是只读命令，随时可安全执行）。

### Agent 安装 / 更新

AI agent（Claude Code、OpenCode、Codex 等）用上面「方式一」的 CLI 命令块即可安装或更新 `ak`。命令幂等——重复执行等于升级已有安装。安装后验证：

```bash
ak list    # 只读表格：全部 skill 的名称 / 作用域 / 归属 agent / 路径
```

### Skill 分发

`agentkeeper` skill 已随仓库分发：`npx skills add yangl326-Dylan/agentkeeper --skill agentkeeper`（Claude Code / Codex / OpenCode / Cursor / Gemini CLI 等）。无注册表的 harness 直接复制文件：DeepSeek Harness `cp skills/agentkeeper/SKILL.md ~/.dsh/skills/agentkeeper.md`；pi `mkdir -p ~/.pi/skills/agentkeeper && cp skills/agentkeeper/SKILL.md ~/.pi/skills/agentkeeper/`；agents 共享目录同理放 `~/.agents/skills/agentkeeper/`。

## Troubleshooting / 常见问题

- `ak` 找不到？确认 `/usr/local/bin` 在 PATH 中（`echo $PATH`）。
- 下载 404？确认 release 已发布：https://github.com/yangl326-Dylan/agentkeeper/releases
- Homebrew cask 在 roadmap 中，欢迎先用上面的方式。
