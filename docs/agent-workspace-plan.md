# Agent Workspace — plan

Turn GingerPaw into a multi-agent coding workspace (Superset-style): tabbed
terminal sessions, one per coding agent (Claude Code, Codex, Gemini CLI, Cursor
CLI), each running in a git worktree, with a diff panel, ports, and PR view.

## Decisions (locked)
- **Scope:** full Superset clone, built in phases.
- **Terminal:** embedded real PTY via **SwiftTerm** (`LocalProcessTerminalView`).
- **Agents:** Claude Code, Codex CLI, Gemini CLI, Cursor CLI.
- **Cat/voice tie-in:** no (kept separate for now).
- **Local only:** skip Superset's CLOUD/MOBILE/SSH groups.
- **Agents must be pre-installed:** detect on `PATH` via a login shell; grey out missing.
- **Worktrees:** auto-created under `~/.gingerpaw/worktrees/<repo>/<branch>`, never the main checkout.

## Domain model
- **Workspace** = a git worktree on a branch (sidebar entry with `+/-` diff stats).
- **Session (tab)** = a terminal running one agent CLI inside the workspace's worktree.
- **3-pane window:** sidebar (workspaces) · center (active session terminal + task input) · right (Files/Changes/Review diff).

## Module layout
- New FlowKit target **`AgentWorkspace`** (depends on SwiftTerm; later a `GitWorktrees` helper).
- `AppCore` depends on it. Phase 0 renders it in the dashboard "Workspaces" tab;
  Phase 1+ moves it to its own window.

## Phases
- **0 — Spike (done):** SwiftTerm `TerminalView` running a login shell in-app. Proves the linchpin.
- **1 — Tabs + agents:** agent registry + detection, tabbed sessions, lobehub logos, new-session flow, folder picker, own window.
- **2 — Workspaces + worktrees:** workspace model, `git worktree add/list/remove`, sidebar with live `git diff --stat`.
- **3 — Diff panel:** Files (git status grouped) + Changes (diff viewer).
- **4 — Ports + PR:** port detection (`lsof` on session PIDs), `gh pr` status/create, RUN/OPEN.
- **5 — Polish:** persistence, automations, shortcuts.

## Linchpin
Everything depends on SwiftTerm running `claude`/`codex` interactively in-app. De-risked in Phase 0.
