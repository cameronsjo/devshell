FROM ubuntu:24.04

ARG VERSION=dev
ARG GIT_COMMIT=unknown
ARG BUILD_TIME=unknown

LABEL org.opencontainers.image.source="https://github.com/cameronsjo/devshell"
LABEL org.opencontainers.image.description="SSH workspace container with Claude Code, tmux, Docker CLI, and modern dev tooling"
LABEL org.opencontainers.image.licenses="MIT"
LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.revision="${GIT_COMMIT}"
LABEL org.opencontainers.image.created="${BUILD_TIME}"

# Bake build metadata into the image (readable at runtime by banner, scripts, etc.)
RUN echo "${VERSION}" > /etc/devshell-version

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# System packages — shell, dev tools, SSH server
RUN apt-get update && apt-get install -y --no-install-recommends \
    # SSH
    openssh-server \
    # Shell
    zsh \
    tmux \
    # Locale (prevents setlocale warnings in hooks/scripts)
    locales \
    # Dev tools
    git \
    jq \
    curl \
    wget \
    htop \
    sudo \
    ca-certificates \
    gnupg \
    unzip \
    # Terminal support (kitty, alacritty, foot, etc.)
    ncurses-term \
    # Build essentials (needed for some mise-managed runtimes)
    build-essential \
    # Diagnostics (network, process, filesystem)
    dnsutils \
    iproute2 \
    strace \
    file \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# Ghostty terminfo (not yet in ncurses-term, compile from source)
COPY rootfs/usr/share/terminfo/ghostty.terminfo /tmp/ghostty.terminfo
RUN tic -x /tmp/ghostty.terminfo && rm /tmp/ghostty.terminfo

# ripgrep, fd-find, bat, delta, fzf — install from GitHub releases (Ubuntu repos are ancient)
RUN ARCH="$(dpkg --print-architecture)" && \
    # ripgrep
    curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/14.1.1/ripgrep_14.1.1-1_${ARCH}.deb" -o /tmp/rg.deb && \
    dpkg -i /tmp/rg.deb && \
    # fd
    curl -fsSL "https://github.com/sharkdp/fd/releases/download/v10.2.0/fd_10.2.0_${ARCH}.deb" -o /tmp/fd.deb && \
    dpkg -i /tmp/fd.deb && \
    # bat
    curl -fsSL "https://github.com/sharkdp/bat/releases/download/v0.24.0/bat_0.24.0_${ARCH}.deb" -o /tmp/bat.deb && \
    dpkg -i /tmp/bat.deb && \
    # delta
    curl -fsSL "https://github.com/dandavison/delta/releases/download/0.18.2/git-delta_0.18.2_${ARCH}.deb" -o /tmp/delta.deb && \
    dpkg -i /tmp/delta.deb && \
    # fzf (apt version too old for --zsh flag)
    curl -fsSL "https://github.com/junegunn/fzf/releases/download/v0.60.3/fzf-0.60.3-linux_${ARCH}.tar.gz" \
    | tar xz -C /usr/local/bin fzf && \
    rm -f /tmp/*.deb

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Docker CLI (not the daemon — we mount the socket)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && apt-get install -y docker-ce-cli docker-compose-plugin && \
    rm -rf /var/lib/apt/lists/*

# Node.js (needed for pnpm, JS/TS tooling — mise manages project-specific versions)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# mise (runtime version manager — installs Node.js, Python, Go into persistent home)
RUN curl https://mise.run | sh && \
    cp /root/.local/bin/mise /usr/local/bin/mise

# uv (Python package manager)
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx

# sops + age (secrets management)
RUN curl -fsSL "https://github.com/getsops/sops/releases/download/v3.9.4/sops-v3.9.4.linux.amd64" \
    -o /usr/local/bin/sops && chmod +x /usr/local/bin/sops && \
    curl -fsSL "https://github.com/FiloSottile/age/releases/download/v1.2.1/age-v1.2.1-linux-amd64.tar.gz" \
    | tar xz -C /tmp && mv /tmp/age/age /usr/local/bin/age && \
    mv /tmp/age/age-keygen /usr/local/bin/age-keygen && rm -rf /tmp/age

# Starship prompt + zoxide (smart cd) — direct binary installs to /usr/local/bin
RUN curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-gnu.tar.gz" \
    | tar xz -C /usr/local/bin starship && \
    curl -fsSL "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.9/zoxide-0.9.9-x86_64-unknown-linux-musl.tar.gz" \
    | tar xz -C /usr/local/bin zoxide

# Charmbracelet tools — gum (TUI prompts), glow (markdown viewer)
RUN ARCH="$(dpkg --print-architecture)" && \
    curl -fsSL "https://github.com/charmbracelet/gum/releases/download/v0.16.0/gum_0.16.0_${ARCH}.deb" -o /tmp/gum.deb && \
    dpkg -i /tmp/gum.deb && \
    curl -fsSL "https://github.com/charmbracelet/glow/releases/download/v2.1.0/glow_2.1.0_${ARCH}.deb" -o /tmp/glow.deb && \
    dpkg -i /tmp/glow.deb && \
    rm -f /tmp/*.deb

# duf (prettier df — disk usage at a glance)
RUN ARCH="$(dpkg --print-architecture)" && \
    curl -fsSL "https://github.com/muesli/duf/releases/download/v0.8.1/duf_0.8.1_linux_${ARCH}.deb" -o /tmp/duf.deb && \
    dpkg -i /tmp/duf.deb && \
    rm -f /tmp/duf.deb

# CodeRabbit CLI (AI code review — auth persists in /home/dev/.coderabbit/ on volume)
RUN curl -fsSL https://cli.coderabbit.ai/install.sh -o /tmp/cr-install.sh && \
    CODERABBIT_INSTALL_DIR=/usr/local/bin sh /tmp/cr-install.sh && \
    rm /tmp/cr-install.sh

# Claude Code (native binary — no Node.js dependency, handles auto-updates)
# Download directly from GCS release bucket, verify checksum, place in PATH
# Fails the build on checksum mismatch so we catch broken installs early
RUN set -e && \
    GCS_BUCKET="https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases" && \
    CC_VERSION=$(curl -fsSL "$GCS_BUCKET/latest") && \
    PLATFORM="linux-x64" && \
    echo "Installing Claude Code ${CC_VERSION} for ${PLATFORM}..." && \
    MANIFEST=$(curl -fsSL "$GCS_BUCKET/$CC_VERSION/manifest.json") && \
    EXPECTED=$(echo "$MANIFEST" | jq -r ".platforms[\"$PLATFORM\"].checksum") && \
    curl -fsSL "$GCS_BUCKET/$CC_VERSION/$PLATFORM/claude" -o /usr/local/bin/claude && \
    ACTUAL=$(sha256sum /usr/local/bin/claude | cut -d' ' -f1) && \
    if [ "$ACTUAL" != "$EXPECTED" ]; then \
        echo "FATAL: checksum mismatch (expected ${EXPECTED}, got ${ACTUAL})" >&2; \
        rm -f /usr/local/bin/claude; \
        exit 1; \
    fi && \
    chmod +x /usr/local/bin/claude && \
    echo "Claude Code ${CC_VERSION} installed (checksum verified)"

# SSH configuration
COPY rootfs/etc/ssh/sshd_config /etc/ssh/sshd_config

# Convenience scripts
COPY scripts/s scripts/p scripts/g scripts/c scripts/m /usr/local/bin/
RUN chmod +x /usr/local/bin/s /usr/local/bin/p /usr/local/bin/g /usr/local/bin/c /usr/local/bin/m

# Login banner (zsh doesn't source /etc/profile.d/, so install to zsh's path)
COPY scripts/devshell-motd.sh /etc/profile.d/devshell-motd.sh
RUN chmod +x /etc/profile.d/devshell-motd.sh && \
    echo '. /etc/profile.d/devshell-motd.sh' >> /etc/zsh/zprofile

# Entrypoint
COPY scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 22

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD pgrep -x sshd || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
