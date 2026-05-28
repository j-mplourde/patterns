# Claude Code: per-client workspaces, shared customizations

A small shell pattern that lets one machine run Claude Code under several
**isolated config directories** (one per client / project / GitHub account)
*without* duplicating your skills, agents, plugins, or root `CLAUDE.md`.

The trick is `CLAUDE_CONFIG_DIR` + a tiny `claude-link` function that
symlinks the shared parts of each workspace back to the central `~/.claude/`.

## Why bother?

Claude Code stores its session history, `.credentials.json`, MCP cache, and
several other things inside `$CLAUDE_CONFIG_DIR` (default `~/.claude/`).
Some of those things you genuinely want **separate** per client:

- session history (don't bleed one client's transcripts into another's)
- credentials (different API keys / accounts)
- MCP server auth state
- per-project settings

…but other things you absolutely want **shared**, because they're your
toolkit and you keep iterating on them:

- `skills/` — your custom slash commands
- `agents/` — your subagent definitions
- `plugins/` — installed plugins
- `CLAUDE.md` — your global development guidelines

Maintaining two copies is a recipe for drift. Symlinks solve it cleanly.

## The shell functions

Drop these into `~/.zshrc` (or `~/.bashrc` with minor tweaks).

```sh
# Items inside ~/.claude that should be SHARED across every workspace.
# Everything else stays per-workspace (sessions, credentials, MCP cache, etc.).
_claude_shared_items=(skills agents plugins CLAUDE.md)

# claude-link <target-dir>
# Point <target-dir>'s shared items at the central ~/.claude. Idempotent.
# If the target already has a real file/dir where the symlink should go,
# we move it aside (.bak.<timestamp>) rather than overwrite.
claude-link() {
  local target="$1"
  mkdir -p "$target"
  local item src dst
  for item in "${_claude_shared_items[@]}"; do
    src="$HOME/.claude/$item"
    dst="$target/$item"
    [[ -e "$src" ]] || continue
    [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]] && continue
    [[ -e "$dst" && ! -L "$dst" ]] && mv "$dst" "$dst.bak.$(date +%s)"
    ln -sfn "$src" "$dst"
  done
}

# One launcher per workspace. Each call:
#   1. ensures the shared symlinks exist (idempotent),
#   2. starts claude with CLAUDE_CONFIG_DIR pointed at the workspace dir,
#   3. seeds the session with a `/color <name>` so you can tell at a glance
#      which client window you're in.
claude-workone() {
  claude-link "$HOME/.claude-workone"
  printf '/color green\n' | CLAUDE_CONFIG_DIR="$HOME/.claude-workone" claude --name workone "$@"
}

claude-worktwo() {
  claude-link "$HOME/.claude-worktwo"
  printf '/color orange\n' | CLAUDE_CONFIG_DIR="$HOME/.claude-worktwo" claude --name worktwo "$@"
}

# Bootstrap a new workspace without launching Claude. Useful when you want to
# pre-create the symlinks (e.g. before copying in a workspace-specific
# settings.json).
claude-init() {
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "usage: claude-init <name>" >&2
    return 1
  fi
  claude-link "$HOME/.claude-$name"
  ls -la "$HOME/.claude-$name"
}
```

After sourcing, `claude-workone` and `claude-worktwo` each give you a
fully-isolated Claude with the same skills, agents, plugins, and `CLAUDE.md`.

## What sits where

```
~/.claude/                          ← the SOURCE OF TRUTH for shared toolkit
├── skills/                         (real)
├── agents/                         (real)
├── plugins/                        (real)
├── CLAUDE.md                       (real)
├── sessions/                       (workspace-specific, not shared)
└── .credentials.json               (workspace-specific, not shared)

~/.claude-workone/                  ← isolated workspace #1
├── skills        -> ~/.claude/skills
├── agents        -> ~/.claude/agents
├── plugins       -> ~/.claude/plugins
├── CLAUDE.md     -> ~/.claude/CLAUDE.md
├── sessions/                       (its own)
└── .credentials.json               (its own)

~/.claude-worktwo/                  ← isolated workspace #2
├── skills        -> ~/.claude/skills     (same target)
├── agents        -> ~/.claude/agents
├── plugins       -> ~/.claude/plugins
├── CLAUDE.md     -> ~/.claude/CLAUDE.md
├── sessions/                       (its own)
└── .credentials.json               (its own)
```

Adding a new skill / agent / plugin to your toolkit means editing **one place**
(`~/.claude/`) and every workspace sees it instantly.

## Adapting it

- **Change what's shared** by editing `_claude_shared_items`. If you also
  want to share `settings.json` (most setups don't, because keybindings/theme
  can differ), add it to the array.
- **More than two workspaces**: copy `claude-workone` and rename. The `--name`
  flag sets the tab title in Claude Code; the `/color <name>` line picks a
  border color so you don't confuse two terminals.
- **macOS vs Linux**: the functions work in both bash and zsh. The
  `date +%s` backup naming is POSIX.

## Caveats

- The symlink target must exist *before* `claude-link` runs, or that item is
  silently skipped (see the `[[ -e "$src" ]] || continue`).
- If a workspace dir contains a real file at one of the shared paths, the
  function backs it up rather than clobber - you'll find a `.bak.<timestamp>`
  sitting next to it. That has saved me from losing a stray `CLAUDE.md`
  override more than once.
- `~/.claude/.credentials.json` is intentionally **not** in the shared list.
  Each workspace authenticates independently.
