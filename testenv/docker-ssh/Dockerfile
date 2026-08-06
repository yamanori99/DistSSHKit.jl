FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV SSH_USER=dev

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

RUN su - "${SSH_USER}" -c \
    'curl --retry 5 --retry-delay 5 --retry-connrefused --connect-timeout 10 \
        -fsSL https://install.julialang.org | sh -s -- --yes' \
    && ln -sf "/home/${SSH_USER}/.juliaup/bin/julia" /usr/local/bin/julia

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
