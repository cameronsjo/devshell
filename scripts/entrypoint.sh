#!/bin/bash
set -euo pipefail

# Configurable UID/GID (default: 1000)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo "Starting devshell with UID=${PUID}, GID=${PGID}"

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

# Ensure user-local bin is on PATH for all login shells
echo 'export PATH="/home/dev/.local/bin:$PATH"' > /etc/profile.d/devshell-path.sh

# Silence default MOTD, we use our own via profile.d
: > /etc/motd

# Ensure home directory structure
mkdir -p /home/dev/.ssh
chmod 700 /home/dev/.ssh

# Create authorized_keys if missing (user drops pubkey into persistent volume)
touch /home/dev/.ssh/authorized_keys
chmod 600 /home/dev/.ssh/authorized_keys

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

# Claude Code — native binary baked into image at /usr/local/bin/claude
# Falls back to npm install if native binary is missing (shouldn't happen — build fails on miss)
if command -v claude > /dev/null 2>&1; then
    CC_VER=$(claude --version 2>/dev/null || echo "unknown")
    echo "Claude Code ready (${CC_VER})"
    # Seed version cache for login banner (avoids slow --version call on every SSH connect)
    echo "${CC_VER}" > /tmp/.claude-version
else
    echo "WARNING: Native Claude Code binary missing, falling back to npm install..."
    CLAUDE_PREFIX="/home/dev/.local"
    su -s /bin/bash dev -c "npm config set prefix '${CLAUDE_PREFIX}' && npm install -g @anthropic-ai/claude-code"
    echo "Claude Code installed via npm fallback"
fi

# Create privilege separation directory
mkdir -p /run/sshd

echo "devshell ready — listening on port 22"

# Start sshd in the foreground (PID 1 for signal handling)
exec /usr/sbin/sshd -D -e
