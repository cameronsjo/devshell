#!/bin/bash
set -euo pipefail

# Configurable UID/GID (default: 1000)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo "Starting devshell with UID=${PUID}, GID=${PGID}"

# ── Volume health check ─────────────────────────────────────
# Detect fresh vs existing volume and validate writability
if [ -f "/home/dev/.local/share/devshell/chezmoi.done" ]; then
    echo "Existing volume detected — incremental provisioning"
else
    echo "Fresh volume detected — full first-boot provisioning will run"
fi

# Remove existing ubuntu user/group that ships with the base image (owns UID/GID 1000)
userdel -r ubuntu 2>/dev/null || true
groupdel ubuntu 2>/dev/null || true

# Create dev group and user
groupadd -g "${PGID}" dev 2>/dev/null || true
if id dev > /dev/null 2>&1; then
    usermod -u "${PUID}" -g "${PGID}" -s /bin/zsh dev
else
    useradd -u "${PUID}" -g "${PGID}" -m -s /bin/zsh -d /home/dev dev
fi

# Unlock account (useradd creates locked accounts — sshd rejects locked users)
passwd -u dev 2>/dev/null || usermod -p '*' dev

# Passwordless sudo
echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
chmod 0440 /etc/sudoers.d/dev

# Ensure user-local bin + Homebrew are on PATH for all login shells
cat > /etc/profile.d/devshell-path.sh << 'PATHEOF'
export PATH="/home/dev/.local/bin:$PATH"
if [ -x /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi
PATHEOF

# Silence default MOTD, we use our own via profile.d
: > /etc/motd

# Validate volume writability before proceeding
if su -s /bin/sh dev -c "touch /home/dev/.volume-ok" 2>/dev/null; then
    rm -f /home/dev/.volume-ok
    echo "Persistent volume verified (writable)"
else
    echo "ERROR: /home/dev is not writable — check volume mount permissions"
    echo "Continuing with potentially ephemeral storage..."
fi

# Ensure home directory structure
mkdir -p /home/dev/.ssh
chmod 700 /home/dev/.ssh

# Authorized keys — start fresh each boot with remote sources, then append local keys
AUTH_KEYS="/home/dev/.ssh/authorized_keys"
LOCAL_KEYS="/home/dev/.ssh/local_keys"
: > "${AUTH_KEYS}"

# Fetch keys from remote identity providers
fetch_keys() {
    local label="$1" url="$2"
    echo "Fetching SSH keys from ${label}..."
    if curl -fsSL --max-time 10 "${url}" >> "${AUTH_KEYS}" 2>/dev/null; then
        echo "SSH keys loaded from ${label}"
    else
        echo "WARNING: Failed to fetch keys from ${label}"
    fi
}

[ -n "${SSHID_USER:-}" ] && fetch_keys "sshid.io/${SSHID_USER}" "https://sshid.io/${SSHID_USER}"
[ -n "${GITHUB_USER:-}" ] && fetch_keys "github.com/${GITHUB_USER}" "https://github.com/${GITHUB_USER}.keys"

# Append any manually-added local keys (persistent volume)
if [ -f "${LOCAL_KEYS}" ] && [ -s "${LOCAL_KEYS}" ]; then
    cat "${LOCAL_KEYS}" >> "${AUTH_KEYS}"
    echo "Local SSH keys appended from ${LOCAL_KEYS}"
fi

chmod 600 "${AUTH_KEYS}"

# Fix ownership on home directory
chown -R "${PUID}:${PGID}" /home/dev

# Docker socket permissions — add dev to docker group matching socket GID
if [ -S /var/run/docker.sock ]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    if getent group docker > /dev/null 2>&1; then
        groupmod -g "${DOCKER_GID}" docker
    else
        groupadd -g "${DOCKER_GID}" docker
    fi
    usermod -aG docker dev
fi

# Persist SSH host keys across container rebuilds
# Store in /home/dev/.ssh/host_keys/ (on the persistent volume)
HOST_KEY_DIR="/home/dev/.ssh/host_keys"
mkdir -p "${HOST_KEY_DIR}"
if [ -f "${HOST_KEY_DIR}/ssh_host_ed25519_key" ]; then
    cp "${HOST_KEY_DIR}"/ssh_host_* /etc/ssh/
    chmod 600 /etc/ssh/ssh_host_*_key
    chmod 644 /etc/ssh/ssh_host_*_key.pub
    echo "Restored SSH host keys from persistent volume"
else
    ssh-keygen -A
    cp /etc/ssh/ssh_host_* "${HOST_KEY_DIR}/"
    echo "Generated new SSH host keys (saved to persistent volume)"
fi

# GitHub deploy key — used by chezmoi to clone private dotfiles repo
# Generated once, persisted on volume. Add the public key as a read-only
# deploy key on the target repo (e.g., cameronsjo/dotfiles).
DEPLOY_KEY="/home/dev/.ssh/github_deploy_key"
if [ ! -f "${DEPLOY_KEY}" ]; then
    su -s /bin/sh dev -c "ssh-keygen -t ed25519 -f ${DEPLOY_KEY} -N '' -C 'devshell-deploy-key'"
    echo "Generated GitHub deploy key — add this public key to your repo:"
    cat "${DEPLOY_KEY}.pub"
fi

# Configure SSH to use the deploy key for github.com
cat > /home/dev/.ssh/config << 'SSHEOF'
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_deploy_key
    IdentitiesOnly yes
    StrictHostKeyChecking accept-new
SSHEOF
chmod 600 /home/dev/.ssh/config
chown "${PUID}:${PGID}" /home/dev/.ssh/config

# Homebrew — symlink /home/linuxbrew → persistent volume so installer's hardcoded path works
BREW_VOLUME="/home/dev/.homebrew"
mkdir -p "${BREW_VOLUME}"
chown "${PUID}:${PGID}" "${BREW_VOLUME}"
if [ ! -L /home/linuxbrew ]; then
    rm -rf /home/linuxbrew
    ln -s "${BREW_VOLUME}" /home/linuxbrew
fi

# First-boot provisioning — Claude Code, language servers, Homebrew, cadence-hooks
# Runs as dev user. Skips anything already installed. Re-run: first-boot.sh
su -s /bin/bash dev -c /usr/local/bin/first-boot.sh

# Seed claude version cache for login banner
CLAUDE_BIN="/home/dev/.local/bin/claude"
if [ -x "${CLAUDE_BIN}" ]; then
    "${CLAUDE_BIN}" --version > /tmp/.claude-version 2>/dev/null || true
fi

# Create privilege separation directory
mkdir -p /run/sshd

echo "devshell ready — listening on port 22"

# Start sshd in the foreground (PID 1 for signal handling)
exec /usr/sbin/sshd -D -e
