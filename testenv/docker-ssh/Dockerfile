FROM ubuntu:24.04

# GHCR package page (description / source / license):
# https://docs.github.com/packages/working-with-a-github-packages-registry/working-with-the-container-registry
LABEL org.opencontainers.image.source="https://github.com/yamanori99/DistSSHKit.jl"
LABEL org.opencontainers.image.documentation="https://github.com/yamanori99/DistSSHKit.jl/blob/main/testenv/docker-ssh/README.md"
LABEL org.opencontainers.image.description="Linux SSH worker for DistSSHKit E2E (sshd, rsync, git, Julia via juliaup). Not the DistSSHKit runtime."
LABEL org.opencontainers.image.licenses="MIT"

ENV DEBIAN_FRONTEND=noninteractive
ENV SSH_USER=dev

# Channels from `.github/julia-slots.env` (major.minor). DEFAULT = slot max,
# ALT = JULIA_E2E_MISMATCH_CHANNEL — both baked so E2E can mismatch then
# `setup --juliaup`.
ARG JULIA_DEFAULT_CHANNEL=1.13
ARG JULIA_ALT_CHANNEL=1.12
ENV DISTSSHKIT_WORKER_JULIA_DEFAULT=${JULIA_DEFAULT_CHANNEL}
ENV DISTSSHKIT_WORKER_JULIA_ALT=${JULIA_ALT_CHANNEL}

RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    openssh-client \
    openssh-server \
    rsync \
    sudo \
    vim-tiny \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -s /bin/bash "${SSH_USER}" \
    && echo "${SSH_USER} ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/${SSH_USER}" \
    && chmod 440 "/etc/sudoers.d/${SSH_USER}"

# Patch floats within each channel; setup --check fails on major.minor mismatch
# without --ignore-julia-version. Default channel matches CI E2E kit parent (max).
# The release pin is the cache key: the channel name stays 1.13 when
# 1.13.0-rc4 becomes 1.13.1, so an unpinned juliaup RUN would stay cached.
ARG JULIA_DEFAULT_RELEASE
ARG JULIA_ALT_RELEASE
RUN set -eu; \
    if [ -z "${JULIA_DEFAULT_RELEASE}" ] || [ -z "${JULIA_ALT_RELEASE}" ]; then \
      echo "JULIA_DEFAULT_RELEASE and JULIA_ALT_RELEASE are required (up.sh resolves them from versions.json)" >&2; \
      exit 1; \
    fi; \
    su - "${SSH_USER}" -c "\
    curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
        -fsSL https://install.julialang.org | sh -s -- --yes --default-channel ${JULIA_DEFAULT_CHANNEL} && \
    \"\$HOME/.juliaup/bin/juliaup\" add ${JULIA_ALT_CHANNEL} && \
    \"\$HOME/.juliaup/bin/juliaup\" default ${JULIA_DEFAULT_CHANNEL}"; \
    ln -sf "/home/${SSH_USER}/.juliaup/bin/julia" /usr/local/bin/julia; \
    su - "${SSH_USER}" -c "\"\$HOME/.juliaup/bin/julia\" --version" > /tmp/julia-default-ver; \
    su - "${SSH_USER}" -c "\"\$HOME/.juliaup/bin/julia\" +${JULIA_ALT_CHANNEL} --version" > /tmp/julia-alt-ver; \
    grep -qx "julia version ${JULIA_DEFAULT_RELEASE}" /tmp/julia-default-ver || { \
      echo "default channel ${JULIA_DEFAULT_CHANNEL} is not ${JULIA_DEFAULT_RELEASE}:" >&2; \
      cat /tmp/julia-default-ver >&2; \
      exit 1; \
    }; \
    grep -qx "julia version ${JULIA_ALT_RELEASE}" /tmp/julia-alt-ver || { \
      echo "alt channel ${JULIA_ALT_CHANNEL} is not ${JULIA_ALT_RELEASE}:" >&2; \
      cat /tmp/julia-alt-ver >&2; \
      exit 1; \
    }; \
    rm -f /tmp/julia-default-ver /tmp/julia-alt-ver

RUN mkdir -p /run/sshd /mounted-keys \
    && mkdir -p "/home/${SSH_USER}/.ssh" \
    && chmod 700 "/home/${SSH_USER}/.ssh" \
    && touch "/home/${SSH_USER}/.ssh/authorized_keys" \
    && chmod 600 "/home/${SSH_USER}/.ssh/authorized_keys" \
    && chown -R "${SSH_USER}:${SSH_USER}" "/home/${SSH_USER}/.ssh" \
    && sed -i 's/#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config \
    && sed -i 's/#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config \
    && ssh-keygen -A

# On start: load mounted-keys/*.pub into authorized_keys; install inter-worker
# identity for dev, then run sshd. (COPY avoids classic-builder heredoc breakage.)
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 22
CMD ["/bin/bash", "/start.sh"]
