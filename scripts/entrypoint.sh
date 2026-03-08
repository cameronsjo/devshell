#!/bin/bash
set -euo pipefail

# Configurable UID/GID (default: 1000)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

echo "Starting devshell with UID=${PUID}, GID=${PGID}"

# Create/update group — use existing group at PGID if one exists, otherwise create 'dev'
EXISTING_GROUP=$(getent group "${PGID}" | cut -d: -f1 || true)
if [ -n "${EXISTING_GROUP}" ]; then
    DEV_GROUP="${EXISTING_GROUP}"
else
    groupadd -g "${PGID}" dev
    DEV_GROUP="dev"
fi

# Create/update user
if id dev > /dev/null 2>&1; then
    usermod -u "${PUID}" -g "${PGID}" -s /bin/zsh dev
else
    useradd -u "${PUID}" -g "${PGID}" -m -s /bin/zsh -d /home/dev dev
fi

# Passwordless sudo
echo "dev ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/dev
chmod 0440 /etc/sudoers.d/dev

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

# Generate host keys if missing (first boot with persistent volume)
ssh-keygen -A

# Create privilege separation directory
mkdir -p /run/sshd

echo "devshell ready — listening on port 22"

# Start sshd in the foreground (PID 1 for signal handling)
exec /usr/sbin/sshd -D -e
