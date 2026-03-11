# Terminal Fixes and Mobile-First Dev Ergonomics — Field Report

**Date:** 2026-03-10
**Type:** pipeline
**Project:** devshell

## Goal

Make the devshell container usable from a mobile SSH app. The session started with broken terminal behavior (garbled backspace, `clear` not working, tmux refusing to start) when connecting from Ghostty, and expanded into building a full suite of single-letter convenience commands that replace typing bash on a phone keyboard.

## Pipeline Overview

The work moved through three layers:

1. **Terminal compatibility** — Fix the foundational issue: the container didn't recognize modern terminal emulators
2. **Claude Code auto-update** — Fix a permissions problem preventing auto-updates
3. **Mobile ergonomics** — Build tap-friendly menus for the operations you'd otherwise type

Each layer depended on the previous one working. No point building nice menus if backspace doesn't work.

```
Ghostty SSH → terminfo fix → working terminal
                                    ↓
                           Claude Code install fix → auto-update works
                                    ↓
                           s/p/g/c/m scripts → mobile-friendly workflow
                                    ↓
                           Login banner → discoverability
```

## What Worked

### Terminfo: ncurses-term + manual Ghostty compilation

Ubuntu 24.04 ships ncurses 6.4, which is missing entries for Ghostty (`xterm-ghostty`), Kitty (`xterm-kitty`), Alacritty (`alacritty`), and Foot (`foot`). Two-layer fix:

- **`ncurses-term` package** — covers Kitty, Alacritty, Foot (~2,400 terminal entries vs the ~20 in `ncurses-base`)
- **Manual `tic -x` compilation** — Ghostty's terminfo was added to ncurses in 6.5 (late 2024), so we export it from the local Ghostty install with `infocmp -x xterm-ghostty` and compile it in the Dockerfile

The `-x` flag on `tic` is critical — Ghostty uses extended capabilities (`Sync`, `Setulc`, `fullkbd`) that get silently dropped without it.

### Claude Code: user-owned npm prefix

Global npm installs (`npm install -g` as root) put packages in `/usr/lib/node_modules/`. When the `dev` user runs Claude Code, auto-update fails because it can't write there. Moving to a user-owned prefix (`/home/dev/.local`) fixes this and has a bonus: the install persists on the volume across container rebuilds.

The entrypoint handles first-run installation:
```bash
su -s /bin/bash dev -c "npm config set prefix '${CLAUDE_PREFIX}' && npm install -g @anthropic-ai/claude-code"
```

### Convenience scripts: gum over fzf

`gum choose` and `gum filter` produce cleaner, more tap-friendly menus than `fzf` for constrained input. Both are in the image, but `gum` is the default for the convenience scripts because:
- Bigger selection targets
- Cleaner visual hierarchy
- Purpose-built input prompts (`gum input`, `gum write`)

## Decisions Made

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Script location | `/usr/local/bin/` | Tools, not config — same category as gum, starship, zoxide |
| Script names | Single letters: s, p, g, c, m | Minimum viable typing on mobile |
| Claude Code install | Entrypoint first-run, not Dockerfile | User-owned for auto-update, persistent volume survives rebuilds |
| MOTD mechanism | `/etc/profile.d/` script | System-wide, doesn't touch user dotfiles |
| PATH extension | `/etc/profile.d/devshell-path.sh` | Works regardless of which dotfiles the user has |
| Menu library | gum (not fzf) | Better for constrained mobile input |
| `c` customization | `~/.commands` file | Batteries included, but swappable |

## Gotchas

- **Ghostty has no standalone terminfo file.** It's generated from Zig source code in the Ghostty repo. The only way to get it is `infocmp -x xterm-ghostty` from a machine that has Ghostty installed, or waiting for your distro to ship ncurses 6.5+.
- **`ncurses-base` is almost useless for modern terminals.** It covers vt100, xterm, screen, linux — nothing from the last decade. `ncurses-term` is the one you want.
- **`/etc/profile.d/` only runs for login shells.** If someone runs `bash` (non-login) they won't see the banner or get the PATH. For SSH sessions this is fine — SSH always starts a login shell.
- **Another Claude session committed a field report mid-session.** Multiple sessions working in the same repo is a real coordination concern — always check `git log` before committing.

## Recommendations

- **Always install `ncurses-term` in dev containers.** It's a few MB and prevents a class of terminal issues that are baffling to debug.
- **Never install global npm packages as root in containers where a non-root user runs them.** The auto-update/permissions problem is predictable and avoidable.
- **`gum` is the right choice for mobile-friendly TUI.** If you're building interactive scripts for constrained input, reach for `gum` first.
- **Test the scripts from an actual mobile SSH app** — the gum menus haven't been validated on a real phone yet.

## Key Takeaways

- Terminal emulator + SSH + container is a three-way terminfo negotiation — the container must have entries for whatever the client advertises via `TERM`
- User-owned installs (`~/.local/` prefix) solve both permissions and persistence in container environments
- Single-letter commands with menu-driven interaction eliminate the mobile SSH typing problem almost entirely
- `/etc/profile.d/` is the right seam for system-wide shell setup in containers — it respects user dotfile ownership while ensuring baseline functionality
- Ship discoverability (the login banner) alongside the tools — features users don't know about don't get used
