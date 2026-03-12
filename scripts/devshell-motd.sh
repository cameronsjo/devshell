#!/bin/bash
# Login banner — shows version info, health checks, and available commands
# Sourced by /etc/zsh/zprofile on login

DEVSHELL_VERSION="unknown"
if [ -f /etc/devshell-version ]; then
    DEVSHELL_VERSION=$(command cat /etc/devshell-version)
fi

CLAUDE_VERSION="not installed"
CLAUDE_VERSION_CACHE="/tmp/.claude-version"
if [ -f "$CLAUDE_VERSION_CACHE" ]; then
    CLAUDE_VERSION=$(command cat "$CLAUDE_VERSION_CACHE")
elif command -v claude &>/dev/null; then
    CLAUDE_VERSION=$(command claude --version 2>/dev/null | head -1 || echo "unknown")
    echo "$CLAUDE_VERSION" > "$CLAUDE_VERSION_CACHE"
fi

# Health checks — surface problems before they bite
WARNINGS=""

if [ ! -S /var/run/docker.sock ]; then
    WARNINGS="${WARNINGS}  !!  Docker socket not mounted\n"
fi

if ! git config user.name &>/dev/null || ! git config user.email &>/dev/null; then
    WARNINGS="${WARNINGS}  !!  Git identity not set (git config --global user.name / user.email)\n"
fi

HOME_USAGE=$(df -h /home/dev 2>/dev/null | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
if [ -n "$HOME_USAGE" ] && [ "$HOME_USAGE" -gt 90 ] 2>/dev/null; then
    WARNINGS="${WARNINGS}  !!  Home volume ${HOME_USAGE}%% full\n"
fi

if [ ! -f /home/dev/.ssh/authorized_keys ] || [ ! -s /home/dev/.ssh/authorized_keys ]; then
    WARNINGS="${WARNINGS}  !!  No SSH authorized_keys (password auth may be disabled)\n"
fi

printf '\n'
printf '  devshell %s  ·  claude %s\n' "$DEVSHELL_VERSION" "$CLAUDE_VERSION"
printf '\n'

if [ -n "$WARNINGS" ]; then
    printf '%b\n' "$WARNINGS"
fi

printf '  s          tmux sessions (pick / create / kill / rename)\n'
printf '  p          project picker (~/Projects, git status indicators)\n'
printf '  g          git menu (status, diff, pull, push, commit, branch)\n'
printf '  c          common commands (docker, htop, disk — customize via ~/.commands)\n'
printf '  m          quick notes (saves to ~/notes/)\n'
printf '\n'
