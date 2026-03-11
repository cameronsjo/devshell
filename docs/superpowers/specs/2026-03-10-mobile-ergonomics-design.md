# Mobile Ergonomics & Claude Code Auto-Update

**Date:** 2026-03-10
**Status:** Approved

## Problem

SSHing into devshell from a mobile app is painful — typing full bash commands
on a touch keyboard leads to garbled input and slow workflows. Additionally,
Claude Code's global npm install (owned by root) prevents auto-updates,
forcing manual intervention.

## Design

### `s` — tmux session manager

**Location:** `/usr/local/bin/s`

Minimal-typing tmux session management via `gum` menus.

| Invocation | Action |
|-----------|--------|
| `s` | List sessions via `gum choose`, pick to attach. Includes "+ New session" option |
| `s foo` | Attach to session "foo" if it exists, otherwise create it |
| `s -k` | Pick a session to kill |
| `s -r` | Pick a session to rename, prompt for new name |

**Behavior:**

- When inside tmux: uses `tmux switch-client` (swap sessions)
- When outside tmux: uses `tmux attach-session`
- If no sessions exist and no arg given: prompts for a name and creates one
- Session list shows attached indicator so you know what's active

### `p` — project picker

**Location:** `/usr/local/bin/p`

Scan projects, pick from a menu, get a named tmux session cd'd into the repo.

| Invocation | Action |
|-----------|--------|
| `p` | Scan `~/Projects` for directories, pick with `gum filter`, open in named tmux session |
| `p foo` | Fuzzy match "foo" against project dirs, skip picker if unique match |

**Behavior:**

- If a tmux session already exists for that project name, attaches to it
- If not, creates a new session named after the directory, cd'd into it
- Inside tmux: switches client. Outside: attaches
- Scans one level deep (`~/Projects/*/`) — not recursive

### Claude Code auto-update fix

**Change:** Move Claude Code from global root-owned npm install to user-owned
install in `/home/dev/.local/`.

- Remove `npm install -g @anthropic-ai/claude-code` from Dockerfile
- Entrypoint checks if `/home/dev/.local/bin/claude` exists
- If not, installs via npm with prefix set to `/home/dev/.local`
- `/home/dev/.local/bin` added to PATH
- Persistent volume means install survives rebuilds
- User owns the files, so auto-update works

## Dependencies

All tools already in the image: `gum`, `fzf`, `tmux`, `npm`, `zsh`.

## Trade-offs

- **`gum` over `fzf`:** Cleaner menus, better for constrained input. `fzf` stays
  available for power-user filtering.
- **Image scripts vs dotfiles:** Scripts in `/usr/local/bin/` are tools, not config.
  Consistent with how `gum`, `starship`, `zoxide` are already shipped.
- **First-run Claude install:** Adds ~10s to first container start. Subsequent starts
  skip it. Worth it for auto-update working correctly.
