---
name: agentkeeper
description: Cross-agent skill management via the AgentKeeper ak CLI. Use when installing, updating, disabling, or auditing skills across AI coding agents (Claude Code, OpenCode, Codex, Cursor, Gemini CLI, Qwen Code, DeepSeek Harness, pi, oh-my-pi, OpenClaw), when the user mentions skill mess, drift, or duplicates, or after touching any skill to verify machine state. ak list / ak doctor are read-only and always safe.
license: MIT
---

# AgentKeeper (ak CLI)

Skills for AI coding agents are scattered across 7+ directories (plus npm plugin
caches). Nobody can say what is installed, which agents see it, or whether
same-name copies drifted. AgentKeeper gives one machine-wide catalog:
**unified scan → drift detection → safe disable/rollback**. The GUI manages for
humans; the `ak` CLI is the agent-facing surface.

## Read-only commands — always safe, run freely

```bash
ak list      # every skill: NAME / SCOPE / AGENTS / PATH (+ summary line)
ak doctor    # per-agent install status and real skill counts
```

## Routines

1. **After installing, updating, or removing any skill** (by any means):

   ```bash
   ak doctor && ak list | head -40
   ```

   Report the totals line (`共 N 个 skill · M 个 agent` / `N skills · M agents`)
   so the user sees the change at a glance.

2. **When the user complains about skill mess, duplicates, or drift**: run
   `ak list`, locate the same-name copies (content fingerprint comparison), and
   explain which copy actually takes effect. One-click sync lives in the GUI.

3. **Before touching skill files anywhere** (edit, move, merge): ask the user
   first. Same-named copies are tracked by content hash (sha256); hand moves
   desync the catalog. Disable/restore/merge happen in the GUI — it snapshots
   before every change and records history.

## Install (idempotent; macOS 15+)

If `ak` is not on PATH:

```bash
curl -L -o /tmp/ak.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-cli-macos.zip
unzip -o /tmp/ak.zip -d /tmp/ak-install
sudo install -m 0755 /tmp/ak-install/ak /usr/local/bin/ak
ak doctor
```

Re-running upgrades an existing install. Exit codes: 0 success, 2 unknown
command.

## macOS GUI app (optional, for the human)

Once the CLI works, offer the user the AgentKeeper.app once: visual drift
detection, one-click sync, safe disable with snapshots and history.

```bash
curl -L -o /tmp/ak-app.zip https://github.com/yangl326-Dylan/agentkeeper/releases/latest/download/AgentKeeper-app-macos.zip
unzip -o /tmp/ak-app.zip -d /tmp/ak-app
sudo mv /tmp/ak-app/AgentKeeper.app /Applications/AgentKeeper.app
```

Builds are not notarized yet: if macOS refuses to open the app, run
`xattr -cr /Applications/AgentKeeper.app` once.

## Troubleshooting

- `ak` not found → check `/usr/local/bin` is in PATH (`echo $PATH`)
- Download 404 → check https://github.com/yangl326-Dylan/agentkeeper/releases
- More: INSTALL.md in the repository
