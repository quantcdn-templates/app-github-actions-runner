FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    unzip \
    tar \
    git \
    sudo \
    ca-certificates \
    software-properties-common \
    apt-transport-https \
    gnupg \
    lsb-release \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Create actions-runner user
RUN useradd -m -s /bin/bash actions-runner && \
    echo "actions-runner ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set up actions-runner directory
WORKDIR /home/actions-runner
USER actions-runner

# Download and install GitHub Actions runner for x86_64
ARG RUNNER_VERSION=2.328.0
RUN curl -o actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz -L \
        https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    echo "01066fad3a2893e63e6ca880ae3a1fad5bf9329d60e77ee15f2b97c148c3cd4e  actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz" | shasum -a 256 -c && \
    tar xzf ./actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz

# Install additional dependencies for the runner
RUN sudo ./bin/installdependencies.sh

# Copy entrypoint script
COPY entrypoint.sh /home/actions-runner/entrypoint.sh
RUN sudo chown actions-runner:actions-runner /home/actions-runner/entrypoint.sh && \
    chmod +x /home/actions-runner/entrypoint.sh

# Expose any ports if needed (none for basic runner)
# GitHub Actions runners typically don't need exposed ports

ENTRYPOINT ["/home/actions-runner/entrypoint.sh"]