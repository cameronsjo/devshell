# devshell

SSH workspace container with Claude Code, tmux, Docker CLI, and modern dev tooling.

Connect from your phone (Termius) or laptop over Tailscale. Not Claude-specific — it's a remote dev shell that happens to have Claude Code installed.

## Quick Start

```bash
# 1. Run the container
docker run -d --name devshell \
  -p 2222:22 \
  -e PUID=1000 -e PGID=1000 \
  -v /path/to/home:/home/dev \
  -v /var/run/docker.sock:/var/run/docker.sock \
  ghcr.io/cameronsjo/devshell:latest

# 2. Drop your SSH public key
docker exec devshell bash -c \
  'echo "ssh-ed25519 AAAA..." >> /home/dev/.ssh/authorized_keys'

# 3. Connect
ssh -p 2222 dev@localhost
```

## What's Inside

| Category | Tools |
|----------|-------|
| Shell | zsh, tmux, fzf, ripgrep, fd, bat, delta |
| Dev | git, gh CLI, jq, curl, wget, htop |
| TUI | gum (interactive prompts), glow (markdown viewer) |
| Runtimes | mise (manages Node.js, Python, Go) |
| AI | Claude Code |
| Infra | Docker CLI, sops, age |
| Python | uv |

Runtimes install into your persistent home on first use via `mise install`. The image stays thin, versions are user-controlled.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PUID` | `1000` | UID for the `dev` user |
| `PGID` | `1000` | GID for the `dev` user |
| `TZ` | (system) | Timezone |

## Persistence

Mount `/home/dev` to a persistent volume. Everything lives there:

- SSH keys and authorized_keys
- Git repos
- mise runtimes (Node.js, Python, Go)
- Claude Code state (`~/.claude/`)
- Shell config (`.zshrc`, `.tmux.conf`)

## Security

- **Auth:** SSH public key only (no passwords)
- **Root:** Disabled (`PermitRootLogin no`)
- **Network:** Designed for Tailscale — not exposed to the internet
- **Docker socket:** Raw mount. Same trust model as `ssh host`

### Verify Image Signature

```bash
cosign verify ghcr.io/cameronsjo/devshell:latest \
  --certificate-identity-regexp="https://github.com/cameronsjo/devshell" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com"
```

## Development

```bash
make build    # Build image locally
make run      # Run test container
make shell    # Shell into test container
make clean    # Clean up
```

## License

MIT
