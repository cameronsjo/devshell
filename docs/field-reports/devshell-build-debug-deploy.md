# Devshell: Build, Debug, Deploy — Field Report

**Date:** 2026-03-08
**Type:** pipeline
**Project:** cameronsjo/devshell + cameronsjo/homelab

## Goal

Create a portable SSH workspace container — Claude Code, tmux, Docker CLI, modern dev tooling — that runs on Unraid and is reachable from Termius on iPhone and SSH from Mac. Full environment parity with the Mac: same dotfiles, same plugins, same rules, same spinner verbs.

## Pipeline Overview

```
Dockerfile + entrypoint.sh + sshd_config
    → GitHub Actions CI (Buildx + Cosign + SLSA)
    → GHCR publish
    → Bosun GitOps deploy (homelab compose)
    → SSH access (Termius + Mac)
    → Dotfiles (chezmoi + manual overrides)
    → Claude Code config (~/.claude/ mirror)
```

Two repos involved:
- **devshell** (new): Dockerfile, entrypoint, sshd config, CI workflow, Makefile
- **homelab** (existing): compose entry, docs, CLAUDE.md update

## What Worked

### Image build pipeline

Ubuntu 24.04 base with tooling installed from GitHub releases (not apt — the apt versions are ancient). CI publishes to GHCR with Cosign keyless signing and SLSA provenance attestation. Build cache via GitHub Actions cache — subsequent builds ~30s.

### Entrypoint pattern

Runtime user creation with UID/GID mapping. The entrypoint runs as root, creates the `dev` user, fixes permissions, detects the Docker socket GID, generates SSH host keys, then `exec`s sshd as PID 1 for signal handling. This is the standard linuxserver.io pattern adapted for SSH.

### Host key persistence

SSH host keys saved to `/home/dev/.ssh/host_keys/` on the persistent volume. Entrypoint restores them on boot if they exist, generates new ones if they don't. Eliminates the "host key changed" warning on every container rebuild.

### Plugin sync via cache copy

`claude plugins install` and related CLI subcommands launch the interactive TUI — they aren't non-interactive CLI commands. The working approach: `tar czf` the entire `~/.claude/plugins/` directory from Mac, `scp` to devshell, extract, then fix paths in `known_marketplaces.json`, `installed_plugins.json`, and `config.json` (replace `/Users/cameron` with `/home/dev`). Claude Code picks up `enabledPlugins` from `settings.json` and handles the rest on first launch.

## What Didn't Work

### Four consecutive container crashes

Each fix required a push → CI build (~2 min) → pull → restart cycle on Unraid. The crashes were:

1. **GID 1000 conflict**: Ubuntu 24.04 ships with a `ubuntu` group at GID 1000. `groupadd -g 1000 dev` failed silently (suppressed by `|| true`), but `useradd` then failed because the group wasn't created. Fix: `groupdel ubuntu` before creating `dev` group.

2. **UID 1000 conflict**: Same root cause — `ubuntu` user at UID 1000. Fix: `userdel -r ubuntu` before creating `dev` user.

3. **Locked account blocks ALL SSH auth**: `useradd` without `-p` creates a locked account (password field is `!` in `/etc/shadow`). OpenSSH rejects ALL authentication methods — including pubkey — for locked accounts. The `sshd -T` config dump shows `PubkeyAuthentication yes` but the account-level lock takes precedence. Fix: `passwd -u dev 2>/dev/null || usermod -p '*' dev` (set password to `*` which means "no password" but "not locked").

4. **MaxAuthTries 3 too low**: Termius offers multiple key types (ECDSA-SK from SSH.id, then ed25519 from 1Password) before finding one the server accepts. Each offer counts against `MaxAuthTries`. At 3, auth was exhausted before the right key was tried. Fix: bumped to 6.

### chezmoi in containers

Three separate issues:

- **TTY prompt error**: chezmoi's `promptStringOnce` requires a TTY even with `--promptString` flags. Fix: pre-create `~/.config/chezmoi/chezmoi.toml` with all template data.
- **run_once scripts need sudo**: The `install-packages-linux.sh` script runs `sudo apt install`. With `no-new-privileges` in the compose, sudo is blocked. Fix: removed `no-new-privileges` from compose (dev shell needs sudo).
- **.gitconfig template calls 1Password**: The `dot_gitconfig.tmpl` template uses `onepasswordRead` for the SSH signing key. No 1Password CLI in the container. Fix: temporarily rename the template, apply everything else, restore it, write `.gitconfig` manually.

### mise symlink to /root

`curl https://mise.run | sh` installs mise to `/root/.local/bin/mise`. The Dockerfile then `ln -s /root/.local/bin/mise /usr/local/bin/mise`. The `dev` user can't traverse `/root/`, so the symlink is dead. Fix: `cp` instead of `ln -s`.

## Decisions Made

| Decision | Rationale |
|----------|-----------|
| Remove `no-new-privileges` | Dev shell needs `sudo` for ad-hoc package installs. The security tradeoff is acceptable — this is an internal SSH workspace behind Tailscale, not a production service |
| Write `.gitconfig` manually | 1Password CLI isn't available in the container. Commit signing is skipped; git credential helper uses `gh auth` instead |
| Copy plugin cache instead of CLI install | The `claude plugins` CLI commands aren't non-interactive — they launch the TUI. Direct file manipulation is the only headless path |
| No Traefik route | SSH-only access. No HTTP service to proxy |
| No Gatus monitoring | SSH isn't HTTP-checkable. Could add a TCP check later |

## Gotchas

- **Ubuntu 24.04 base image ships `ubuntu` user at UID/GID 1000** — this is new as of 24.04. Previous LTS (22.04) didn't have this. Any container that creates a custom user at UID 1000 needs to remove `ubuntu` first.

- **Locked accounts in Linux are absolute** — they block ALL auth methods, not just password. This is documented in `shadow(5)` but easy to miss when you're only using pubkey auth. The symptom in sshd logs is `User dev not allowed because account is locked`.

- **SSH.id is Termius's passkey hosting service** — device-bound ECDSA-SK keys tied to biometric auth. The public keys are available at `sshid.io/<username>`. They generate ECDSA-SK keys (not ed25519-sk), which are hardware-bound and can't be exported.

- **macOS `scp -r` follows symlinks differently** — the plugin cache had symlinks that broke `scp -r`. Fix: `tar czf` → `scp` → `tar xzf`.

- **macOS tar adds xattr metadata** — `LIBARCHIVE.xattr.com.apple.provenance` warnings on Linux extraction. Harmless but noisy.

## Setup / Reproduction

### First boot

```bash
# On Unraid — create persistent home
ssh unraid 'mkdir -p /mnt/user/appdata/devshell/home/.ssh'

# Drop SSH public key
ssh unraid 'echo "ssh-ed25519 AAAA... user@host" >> /mnt/user/appdata/devshell/home/.ssh/authorized_keys'

# Deploy via Bosun (push homelab compose change)
# Or manual: docker compose -f /mnt/user/appdata/compose/apps.yml up -d devshell
```

### Dotfiles setup (after first SSH)

```bash
# Auth GitHub CLI
gh auth login --with-token <<< "ghp_..."
gh auth setup-git

# Clone dotfiles and apply (skip broken templates + scripts)
chezmoi init cameronsjo
mv ~/.local/share/chezmoi/dot_gitconfig.tmpl ~/.local/share/chezmoi/dot_gitconfig.tmpl.skip
chezmoi apply --exclude=scripts,encrypted --force
mv ~/.local/share/chezmoi/dot_gitconfig.tmpl.skip ~/.local/share/chezmoi/dot_gitconfig.tmpl

# Write .gitconfig manually (no 1Password for signing)
# ... (see entrypoint session for full content)
```

### Claude Code setup

```bash
claude login    # Opens OAuth URL — copy to phone browser
# Plugins are pre-configured via settings.json + cache copy
```

## Key Takeaways

- **Ubuntu 24.04 containers need `userdel -r ubuntu`** before creating custom users at UID 1000. This will bite every containerized dev environment built on 24.04.
- **Locked accounts block pubkey SSH** — always unlock accounts created by `useradd`, even if you're only using key-based auth.
- **Claude Code plugin management is TUI-only** — there are no non-interactive CLI commands for install/enable. Mirror the Mac's `~/.claude/plugins/` directory and edit `settings.json` directly.
- **Host key persistence eliminates rebuild friction** — save to the persistent volume, restore in entrypoint. One-time fingerprint acceptance instead of per-rebuild.
- **`no-new-privileges` and `sudo` are mutually exclusive** — choose one. For dev shells, sudo wins.
