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
is_done() { [ -f "${STAMP_DIR}/$1.done" ]; }

# ── Oh-My-Zsh ────────────────────────────────────────────────
if [ -d "${HOME}/.oh-my-zsh" ]; then
    echo "Oh-My-Zsh ready"
elif ! is_done oh-my-zsh; then
    echo "Installing Oh-My-Zsh..."
    RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    stamp oh-my-zsh
    echo "Oh-My-Zsh installed"
fi

# ── Chezmoi (dotfiles) ──────────────────────────────────────
# Provisions .zshrc, .gitconfig, starship.toml, and other shell config.
# On first boot: init from GitHub repo with headless=true (no 1Password).
# On subsequent boots: apply any upstream changes.
CHEZMOI_CONFIG="${HOME}/.config/chezmoi/chezmoi.toml"
if [ -f "${CHEZMOI_CONFIG}" ]; then
    echo "Chezmoi ready — applying dotfiles..."
    chezmoi apply --no-tty || echo "WARNING: chezmoi apply failed (non-fatal)"
elif ! is_done chezmoi; then
    echo "Initializing chezmoi from cameronsjo/dotfiles..."
    if chezmoi init cameronsjo/dotfiles --no-tty --apply \
        --promptString name="Cameron Sjo" \
        --promptString email="cameronsjo@users.noreply.github.com" \
        --promptString obsidianVault="/vault" \
        --promptString projectsDir="~/Projects" \
        --promptBool headless=true; then
        stamp chezmoi
        echo "Chezmoi initialized and applied"
    else
        echo "WARNING: chezmoi init failed (non-fatal) — dotfiles not provisioned"
        echo "Re-run manually: chezmoi init cameronsjo/dotfiles --apply"
    fi
fi

# ── Claude Code ──────────────────────────────────────────────
# Native installer places binary at ~/.claude/bin/claude (on persistent volume)
if [ -x "${HOME}/.claude/bin/claude" ]; then
    echo "Claude Code ready ($(${HOME}/.claude/bin/claude --version 2>/dev/null || echo 'unknown'))"
elif ! is_done claude-code; then
    echo "Installing Claude Code..."
    curl -fsSL https://claude.ai/install.sh | bash
    # Clean up legacy npm install if present
    if [ -L "${PREFIX}/bin/claude" ]; then
        rm -f "${PREFIX}/bin/claude"
        rm -rf "${PREFIX}/lib/node_modules/@anthropic-ai/claude-code"
    fi
    stamp claude-code
    echo "Claude Code installed ($(${HOME}/.claude/bin/claude --version 2>/dev/null || echo 'unknown'))"
fi

# ── Language servers (for Claude Code LSP plugins) ───────────
# All npm-based servers install to the same prefix on the volume.
# Update: npm update -g <package>

if ! is_done lsp-servers; then
    echo "Installing language servers..."
    npm config set prefix "${PREFIX}"
    npm install -g typescript typescript-language-server pyright
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

# ── Bun (bunx runner + fast JS/TS toolkit) ───────────────────
if [ -x "${PREFIX}/bin/bun" ]; then
    echo "Bun ready ($(${PREFIX}/bin/bun --version 2>/dev/null || echo 'unknown'))"
elif ! is_done bun; then
    echo "Installing Bun..."
    curl -fsSL https://bun.sh/install | BUN_INSTALL="${PREFIX}" bash
    stamp bun
    echo "Bun installed ($(${PREFIX}/bin/bun --version 2>/dev/null || echo 'unknown'))"
fi

# ── Homebrew + cadence-hooks ─────────────────────────────────
if [ -x "${BREW_PREFIX}/bin/brew" ]; then
    echo "Homebrew ready"
elif ! is_done homebrew; then
    echo "Installing Homebrew..."
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(${BREW_PREFIX}/bin/brew shellenv)"
    brew tap cameronsjo/tap
    brew install cadence-hooks
    stamp homebrew
    echo "Homebrew + cadence-hooks installed"
fi

echo "First-boot provisioning complete"
