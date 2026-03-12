# Persistent Volume Provisioning Pattern — Field Report

**Date:** 2026-03-11
**Type:** architecture
**Project:** devshell

## Goal

Move all runtime tools (Claude Code, language servers, Homebrew, Bun) off the Docker image and onto the persistent `/home/dev` volume so they can self-update without image rebuilds. Keep the image lean (OS packages + static binaries only) while making first boot fully automatic.

## Architecture

The devshell image has two layers of tooling:

| Layer | Lives in | Survives rebuild | Update mechanism |
|---|---|---|---|
| **OS packages** | `/usr/bin/`, `/usr/local/bin/` | No (baked in image) | Rebuild image |
| **Runtime tools** | `/home/dev/.local/`, `/home/dev/.homebrew/` | Yes (persistent volume) | `claude update`, `npm update -g`, `brew upgrade`, `bun upgrade` |

The boundary: if it's an apt package or a static binary with no self-update story, bake it. If it has its own update mechanism or changes frequently, provision it to the volume.

### The First-Boot Script

`scripts/first-boot.sh` runs as the `dev` user from the entrypoint on every container start. It uses **stamp files** for idempotency:

```
~/.local/share/devshell/
├── claude-code.done
├── lsp-servers.done
└── bun.done
```

Each section checks `done <name>` before running. On first boot, everything installs. On subsequent boots, everything skips. Force reinstall any section: `rm ~/.local/share/devshell/<name>.done && first-boot.sh`.

The stamp file pattern was chosen over binary existence checks because:
- A binary might exist from a previous manual install with different configuration
- Stamp files explicitly track what *our provisioning* completed
- Easy to force-reinstall individual sections without affecting others

### The Homebrew Symlink Trick

Homebrew's Linux installer hardcodes `/home/linuxbrew/.linuxbrew` as its prefix. This directory isn't on the persistent volume (`/home/dev`). The solution:

```
/home/linuxbrew → /home/dev/.homebrew (symlink, created by entrypoint as root)
```

The installer thinks it's writing to `/home/linuxbrew/.linuxbrew/` but actually lands at `/home/dev/.homebrew/.linuxbrew/`. The symlink must be created by the entrypoint (runs as root) before `first-boot.sh` (runs as dev) executes.

### npm Prefix for User-Owned Installs

Claude Code, TypeScript language server, and Pyright all install via npm. The prefix is set to `/home/dev/.local`:

```bash
npm config set prefix /home/dev/.local
npm install -g @anthropic-ai/claude-code
```

This puts binaries in `/home/dev/.local/bin/` (already first on PATH) and the dev user owns everything — no sudo needed for updates.

## Decisions Made

**Stamp files over binary checks.** Binary existence is ambiguous (who installed it? what version? what config?). Stamp files are explicit, per-section, and cheap. Trade-off: you need to know to delete the stamp file to force a reinstall.

**npm over native binary for Claude Code.** The previous approach downloaded a native binary from a GCS bucket with checksum verification. It was fragile — the `[ "$ACTUAL" = "$EXPECTED" ] && chmod` pattern silently continued on checksum failure. npm is the official install path, handles architecture detection, and enables `claude update` for self-updates.

**Entrypoint stays root-only, first-boot runs as dev.** The entrypoint handles root tasks (user creation, SSH keys, docker socket, symlinks) then delegates to `first-boot.sh` via `su -s /bin/bash dev`. Clean separation of privilege.

**gopls is conditional.** It needs the Go runtime, which comes from mise. First boot won't have Go yet, so the script logs "gopls skipped" and you re-run after `mise install go`.

## Gotchas

**`cat` aliased to `bat` in sourced scripts.** The login banner script is *sourced* into zsh (not executed as a subprocess), so it inherits shell aliases. A heredoc through `cat` would go through `bat` with syntax highlighting and paging. Fixed by switching to `printf` statements.

**Homebrew installer ignores `HOMEBREW_PREFIX` on Linux.** Despite the env var existing, the installer always uses `/home/linuxbrew/.linuxbrew`. The symlink redirect was the only clean workaround.

**Piping curl to sh with env vars doesn't work as expected.** `VAR=x curl ... | sh` sets the var for `curl`, not for `sh`. You need to download first, then `VAR=x sh /tmp/script.sh`.

**Claude Code `--version` is slow.** Running it on every SSH login adds noticeable latency. Solved by caching the version string at `/tmp/.claude-version` during container start (entrypoint seeds it), and the banner reads the cache file instead.

## Key Takeaways

- **Stamp files beat binary existence checks** for idempotent provisioning — explicit, per-section, and you can force-reinstall by deleting one file
- **Symlink the parent directory** when an installer hardcodes a prefix — redirect the entire tree, not individual files
- **Cache slow subprocess calls** that run on every login — seed the cache at container start when you're already running the tool
- **Sourced scripts inherit aliases** — use `command cat` or `printf` instead of bare `cat` in anything loaded by `.zshrc` / `.zprofile`
- **The image/volume boundary** is the key architectural decision: bake what's static, provision what self-updates
