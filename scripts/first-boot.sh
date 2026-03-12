#!/bin/bash
# First-boot provisioning — installs tools to persistent volume
# Runs as the dev user. Skips anything already installed.
# Re-run manually: su -s /bin/bash dev -c /usr/local/bin/first-boot.sh
set -euo pipefail

PREFIX="/home/dev/.local"
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
STAMP_DIR="/home/dev/.local/share/devshell"
mkdir -p "${STAMP_DIR}"

# Stamp file pattern — skip sections that already completed
stamp() { touch "${STAMP_DIR}/$1.done"; }
done() { [ -f "${STAMP_DIR}/$1.done" ]; }

# ── Claude Code ──────────────────────────────────────────────
if [ -x "${PREFIX}/bin/claude" ]; then
    echo "Claude Code ready ($(${PREFIX}/bin/claude --version 2>/dev/null || echo 'unknown'))"
elif ! done claude-code; then
    echo "Installing Claude Code..."
    npm config set prefix "${PREFIX}"
    npm install -g @anthropic-ai/claude-code
    stamp claude-code
    echo "Claude Code installed ($(${PREFIX}/bin/claude --version 2>/dev/null || echo 'unknown'))"
fi

# ── Language servers (for Claude Code LSP plugins) ───────────
# All npm-based servers install to the same prefix on the volume.
# Update: npm update -g <package>

if ! done lsp-servers; then
    echo "Installing language servers..."
    npm config set prefix "${PREFIX}"

    # TypeScript / JavaScript
    npm install -g typescript typescript-language-server

    # Python
    npm install -g pyright

    stamp lsp-servers
    echo "Language servers installed"
else
    echo "Language servers ready"
fi

# gopls — needs Go runtime (mise installs it)
if command -v go &>/dev/null; then
    if ! command -v gopls &>/dev/null; then
        echo "Installing gopls..."
        GOBIN="${PREFIX}/bin" go install golang.org/x/tools/gopls@latest
        echo "gopls installed"
    else
        echo "gopls ready"
    fi
else
    echo "gopls skipped (install Go via mise first, then re-run)"
fi

# ── Homebrew + cadence-hooks ─────────────────────────────────
if [ -x "${BREW_PREFIX}/bin/brew" ]; then
    echo "Homebrew ready"
else
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(${BREW_PREFIX}/bin/brew shellenv)"
    brew tap cameronsjo/tap
    brew install cadence-hooks
    echo "Homebrew + cadence-hooks installed"
fi

echo "First-boot provisioning complete"
