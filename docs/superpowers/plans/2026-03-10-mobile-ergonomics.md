# Mobile Ergonomics & Claude Code Auto-Update Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add tap-friendly tmux session management (`s`) and project picker (`p`) scripts, and fix Claude Code auto-update by moving to a user-owned install.

**Architecture:** Shell scripts in `/usr/local/bin/` using `gum` for TUI menus. Claude Code moves from root-owned global npm to user-owned install in `/home/dev/.local/` via entrypoint first-run logic.

**Tech Stack:** bash, gum, tmux, npm

---

## File Structure

| File | Action | Purpose |
|------|--------|---------|
| `scripts/s` | Create | tmux session manager script |
| `scripts/p` | Create | Project picker script |
| `scripts/entrypoint.sh` | Modify | Add Claude Code first-run install, PATH setup |
| `Dockerfile` | Modify | COPY scripts, remove global claude install, keep nodejs |

Scripts live in `scripts/` in the repo and get COPY'd to `/usr/local/bin/` in the Dockerfile (same pattern as `entrypoint.sh`).

---

## Chunk 1: tmux session manager (`s`)

### Task 1: Create the `s` script

**Files:**
- Create: `scripts/s`

- [ ] **Step 1: Create `scripts/s` with session picker logic**

```bash
#!/bin/bash
# s — tmux session manager
# Usage: s          (pick session or create new)
#        s <name>   (attach/create session by name)
#        s -k       (pick session to kill)
#        s -r       (pick session to rename)
set -euo pipefail

attach_or_switch() {
    local session="$1"
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$session"
    else
        tmux attach-session -t "$session"
    fi
}

create_session() {
    local name="$1"
    tmux new-session -d -s "$name"
    attach_or_switch "$name"
}

list_sessions() {
    tmux list-sessions -F "#S#{?session_attached, (attached),}" 2>/dev/null
}

# -k: kill a session
if [ "${1:-}" = "-k" ]; then
    sessions="$(list_sessions)" || { echo "No sessions."; exit 0; }
    target="$(echo "$sessions" | gum choose --header "Kill which session?")"
    target="${target%% *}"
    tmux kill-session -t "$target"
    echo "Killed: $target"
    exit 0
fi

# -r: rename a session
if [ "${1:-}" = "-r" ]; then
    sessions="$(list_sessions)" || { echo "No sessions."; exit 0; }
    target="$(echo "$sessions" | gum choose --header "Rename which session?")"
    target="${target%% *}"
    new_name="$(gum input --placeholder "New name" --header "Rename '$target' to:")"
    [ -z "$new_name" ] && exit 1
    tmux rename-session -t "$target" "$new_name"
    echo "Renamed: $target → $new_name"
    exit 0
fi

# s <name>: attach or create by name
if [ -n "${1:-}" ]; then
    if tmux has-session -t "$1" 2>/dev/null; then
        attach_or_switch "$1"
    else
        create_session "$1"
    fi
    exit 0
fi

# s (no args): pick from list or create new
sessions="$(list_sessions 2>/dev/null)" || sessions=""

if [ -z "$sessions" ]; then
    name="$(gum input --placeholder "Session name" --header "No sessions. Create one:")"
    [ -z "$name" ] && exit 1
    create_session "$name"
else
    choice="$(printf "+ New session\n%s" "$sessions" | gum choose --header "Sessions")"
    if [ "$choice" = "+ New session" ]; then
        name="$(gum input --placeholder "Session name" --header "New session name:")"
        [ -z "$name" ] && exit 1
        create_session "$name"
    else
        target="${choice%% *}"
        attach_or_switch "$target"
    fi
fi
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/s`

- [ ] **Step 3: Commit**

```bash
git add scripts/s
git commit -m "feat: add tmux session manager script (s)"
```

---

## Chunk 2: Project picker (`p`)

### Task 2: Create the `p` script

**Files:**
- Create: `scripts/p`

- [ ] **Step 1: Create `scripts/p` with project picker logic**

```bash
#!/bin/bash
# p — project picker
# Usage: p          (pick project, open in named tmux session)
#        p <query>  (fuzzy match project name, skip picker if unique)
set -euo pipefail

PROJECTS_DIR="${HOME}/Projects"

attach_or_switch() {
    local session="$1"
    if [ -n "${TMUX:-}" ]; then
        tmux switch-client -t "$session"
    else
        tmux attach-session -t "$session"
    fi
}

open_project() {
    local dir="$1"
    local name
    name="$(basename "$dir")"

    # If session exists, just attach
    if tmux has-session -t "$name" 2>/dev/null; then
        attach_or_switch "$name"
        return
    fi

    # Create session cd'd into the project
    tmux new-session -d -s "$name" -c "$dir"
    attach_or_switch "$name"
}

# Gather project directories (one level deep)
if [ ! -d "$PROJECTS_DIR" ]; then
    echo "No ~/Projects directory found."
    exit 1
fi

projects="$(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)"
if [ -z "$projects" ]; then
    echo "No projects found in ~/Projects."
    exit 1
fi

project_names="$(echo "$projects" | xargs -I{} basename {})"

# p <query>: fuzzy match, skip picker if unique
if [ -n "${1:-}" ]; then
    matches="$(echo "$project_names" | grep -i "$1" || true)"
    match_count="$(echo "$matches" | grep -c . || true)"

    if [ "$match_count" -eq 1 ]; then
        open_project "${PROJECTS_DIR}/${matches}"
        exit 0
    elif [ "$match_count" -eq 0 ]; then
        echo "No project matching '$1'."
        exit 1
    fi
    # Multiple matches — fall through to picker with filter pre-applied
    project_names="$matches"
fi

# Interactive pick
choice="$(echo "$project_names" | gum filter --header "Projects")"
[ -z "$choice" ] && exit 1
open_project "${PROJECTS_DIR}/${choice}"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x scripts/p`

- [ ] **Step 3: Commit**

```bash
git add scripts/p
git commit -m "feat: add project picker script (p)"
```

---

## Chunk 3: Claude Code auto-update fix

### Task 3: Move Claude Code to user-owned install

**Files:**
- Modify: `Dockerfile:114-119` — remove global npm install of claude, keep nodejs
- Modify: `scripts/entrypoint.sh:66-68` — add Claude Code first-run install before sshd starts

- [ ] **Step 1: Update Dockerfile — remove global claude install, keep nodejs**

Replace lines 114-119:
```dockerfile
# Node.js runtime (needed for Claude Code — installed per-user at first boot)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*
```

- [ ] **Step 2: Update entrypoint — add Claude Code first-run install**

Add after the SSH host keys block (before "Create privilege separation directory"):
```bash
# Claude Code — install to user-owned prefix on first run
# Persistent volume means this survives rebuilds; user ownership enables auto-update
CLAUDE_PREFIX="/home/dev/.local"
if [ ! -x "${CLAUDE_PREFIX}/bin/claude" ]; then
    echo "Installing Claude Code to ${CLAUDE_PREFIX}..."
    su -s /bin/bash dev -c "npm config set prefix '${CLAUDE_PREFIX}' && npm install -g @anthropic-ai/claude-code"
    echo "Claude Code installed"
else
    echo "Claude Code already installed (skipping)"
fi
```

- [ ] **Step 3: Ensure PATH includes user-local bin**

Add after the user creation block in entrypoint.sh — write a profile snippet:
```bash
# Ensure user-local bin is on PATH for all login shells
echo 'export PATH="/home/dev/.local/bin:$PATH"' > /etc/profile.d/devshell-path.sh
```

- [ ] **Step 4: Commit**

```bash
git add Dockerfile scripts/entrypoint.sh
git commit -m "fix: move Claude Code to user-owned install for auto-update support"
```

---

## Chunk 4: Wire scripts into the image

### Task 4: Add COPY and chmod for s and p in Dockerfile

**Files:**
- Modify: `Dockerfile:124-126` — add COPY for s and p alongside entrypoint

- [ ] **Step 1: Update Dockerfile to copy convenience scripts**

Replace the entrypoint COPY block:
```dockerfile
# Convenience scripts
COPY scripts/s /usr/local/bin/s
COPY scripts/p /usr/local/bin/p
RUN chmod +x /usr/local/bin/s /usr/local/bin/p

# Entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh
```

- [ ] **Step 2: Commit**

```bash
git add Dockerfile
git commit -m "feat: add s and p convenience scripts to image"
```

---

## Verification

After building (`make build` or `docker build -t devshell .`):

1. **`s` works:** Run `s` — should show gum picker with "+ New session". Create one, verify attach. Run `s test` — should create/attach session named "test".
2. **`p` works:** Create `~/Projects/foo` inside container. Run `p` — should show "foo" in picker. Select it — should create tmux session "foo" cd'd into the dir.
3. **Claude Code auto-update:** First boot should show "Installing Claude Code..." message. Second boot should show "already installed (skipping)". Run `claude --version` as dev user. Check that auto-update doesn't error.
4. **PATH:** `echo $PATH` should include `/home/dev/.local/bin`.
