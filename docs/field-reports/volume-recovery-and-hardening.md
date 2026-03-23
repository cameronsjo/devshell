# Devshell Volume Recovery and Hardening — Field Report

**Date:** 2026-03-22
**Type:** investigation
**Project:** cameronsjo/devshell

## Goal

The devshell container on Unraid wouldn't start — SSH refused, container stuck in Created state. The investigation uncovered a stale container conflict, volume data loss, and the absence of any reproducible provisioning for shell config and dotfiles. The session pivoted from "fix SSH" to "make the entire devshell recoverable from a blank volume."

## Root Cause

The container `6aff866c5abd_devshell` was created from an old compose config that bind-mounted `first-boot.sh` from the host. That file no longer existed at the expected path, so the container never started. The hash-prefixed name indicated a naming conflict with a newer container.

The persistent volume at `/mnt/user/appdata/devshell/home` had no data — the old container never ran the entrypoint, so it never populated the home directory. A month of work in a previous devshell instance was stored on a volume that is now unrecoverable (cause unclear — possibly the stale container conflict, possibly an Unraid share/mover issue).

## What We Tried

### 1. Diagnosing the SSH failure

Traced the connection from Termius logs through the container state. Found the container was in Created (never Started) state. The bind-mount error in Docker logs pointed directly at the stale config.

### 2. Fixing the stale `.ssh` directory

After removing the old container and bringing up a fresh one, `.ssh/authorized_keys` returned a stale file handle. We ran `rm -rf .ssh && docker restart` to clear it. This worked, but the stale handle was a symptom of the broader volume corruption — the entire volume was empty.

**Lesson:** Stale file handles on a container volume indicate potential volume-level issues. Check multiple paths and overall volume size before deleting anything inside it.

### 3. Searching for old data

Checked `/mnt/user/appdata/devshell/home/` (FUSE user share), `/mnt/cache/`, and individual disks. All timestamps were from the current boot. The old data was not on any accessible disk.

**Lesson:** Never query `/mnt/disk*` directly on Unraid — always use `/mnt/user/`. The FUSE user share layer is the only correct interface.

### 4. Building reproducible provisioning

With no data to recover, the focus shifted to making future volume losses non-destructive. This became the bulk of the session.

## What Worked

### Chezmoi headless mode

Added a `headless` boolean template variable to the chezmoi dotfiles. When `true`:
- `onepasswordRead` calls are skipped (no 1Password CLI needed)
- Git commit signing is disabled
- 1Password SSH agent sock is not exported

This makes the same dotfiles repo work on macOS (with 1Password) and in containers (without).

**Key detail:** `promptStringOnce` reads from the chezmoi config file, not `--promptString` CLI flags. Non-interactive init requires pre-seeding `~/.config/chezmoi/chezmoi.toml` before running `chezmoi init`.

### GitHub deploy key pattern

The devshell entrypoint generates an ed25519 keypair at `/home/dev/.ssh/github_deploy_key` on first boot. The SSH config routes `github.com` through this key. The public key is added as a read-only deploy key on the private dotfiles repo.

This avoids:
- Making the dotfiles repo public
- Storing PATs in compose files
- Requiring 1Password or manual key management

The key persists on the volume. If the volume is lost, a new key is generated and the deploy key on GitHub needs to be updated — a one-time manual step.

### Docker container detection

The chezmoi `run_once_before_install-packages-linux.sh.tmpl` script checks for `/.dockerenv` and exits early inside Docker. This prevents redundant `apt install` of packages already baked into the image.

### Volume health check

The entrypoint now validates volume writability before proceeding and logs whether the boot is fresh or incremental. This makes `docker logs devshell` diagnostic without SSH access.

## What Didn't Work

### HTTPS clone for private repos

`chezmoi init cameronsjo/dotfiles` uses HTTPS by default. Inside a non-interactive container, git prompts for credentials and fails. The `--no-tty` flag doesn't help — git itself needs auth.

### `--promptString` with `promptStringOnce`

These are different chezmoi template functions. `--promptString` populates `promptString`, not `promptStringOnce`. The fix was to pre-seed the config file instead of using CLI flags.

### SSH config ownership

The entrypoint's `chown -R` runs before the deploy key section, so the SSH config file written afterward is owned by root. The dev user can't read it. Fixed by adding `chown` after writing the config.

## Gotchas

- **Docker prune required:** Unraid's Docker loop device was 100% full (100GB used). `docker system prune -af` freed 30GB+ but took several minutes.
- **Container restart loop:** `set -euo pipefail` in `first-boot.sh` meant any provisioning failure killed the script, which prevented sshd from starting. Wrapped chezmoi init in a conditional so failure is non-fatal.
- **Deploy key rotation on volume loss:** If the volume is destroyed, the deploy key is regenerated with a new fingerprint. The old key on GitHub must be replaced manually. This is an acceptable trade-off for the simplicity of the approach.

## Decisions Made

| Decision | Rationale |
|---|---|
| Deploy key over PAT | Least privilege — scoped to one repo, no token in compose file |
| Pre-seed config over CLI flags | `promptStringOnce` reads config file, not CLI args |
| Non-fatal chezmoi failure | Container must boot and serve SSH even if dotfiles fail |
| Container over VM | Dockerfile is single source of truth for tooling; fast rebuilds; Docker socket passthrough |
| Headless flag over separate dotfiles | One repo, one truth — gated by template variable |

## Setup / Reproduction

To set up a new devshell from scratch:

1. Deploy the container with `GITHUB_USER` and `SSHID_USER` env vars set
2. Wait for first boot to complete (generates deploy key)
3. Grab the public key: `docker exec devshell cat /home/dev/.ssh/github_deploy_key.pub`
4. Add it as a read-only deploy key on `cameronsjo/dotfiles`
5. Re-run first-boot: `docker exec -u dev devshell first-boot.sh`
6. Chezmoi will clone and apply dotfiles automatically

Subsequent boots re-apply chezmoi (picks up upstream changes) and skip already-provisioned tools.

## Key Takeaways

- Stale file handles on container volumes are a symptom, not the disease — check the full volume before acting on individual files
- Never query Unraid disks directly (`/mnt/disk*`) — always use the FUSE user share at `/mnt/user/`
- `promptStringOnce` in chezmoi reads from the config file, not `--promptString` flags — pre-seed the config for non-interactive init
- Deploy keys are the right auth pattern for containers accessing private repos — scoped, no tokens in config, auto-generated
- First-boot provisioning failures must be non-fatal — the container's primary job (SSH server) must always come up
