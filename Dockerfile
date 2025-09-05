FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies including Docker for BuildKit integration
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
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli docker-buildx-plugin \
    && rm -rf /var/lib/apt/lists/*

# Set up runner directory
WORKDIR /runner

# Download and install GitHub Actions runner (multi-arch)
ARG TARGETARCH
ARG RUNNER_VERSION=2.328.0

# Set architecture-specific variables
RUN case ${TARGETARCH} in \
        amd64) \
            ARCH_NAME="x64" && \
            CHECKSUM="01066fad3a2893e63e6ca880ae3a1fad5bf9329d60e77ee15f2b97c148c3cd4e" \
        ;; \
        arm64) \
            ARCH_NAME="arm64" && \
            CHECKSUM="b801b9809c4d9301932bccadf57ca13533073b2aa9fa9b8e625a8db905b5d8eb" \
        ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
        ;; \
    esac && \
    curl -o actions-runner-linux-${ARCH_NAME}-${RUNNER_VERSION}.tar.gz -L \
        https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH_NAME}-${RUNNER_VERSION}.tar.gz && \
    echo "${CHECKSUM}  actions-runner-linux-${ARCH_NAME}-${RUNNER_VERSION}.tar.gz" | shasum -a 256 -c && \
    tar xzf ./actions-runner-linux-${ARCH_NAME}-${RUNNER_VERSION}.tar.gz && \
    rm actions-runner-linux-${ARCH_NAME}-${RUNNER_VERSION}.tar.gz

# Install additional dependencies for the runner
RUN ./bin/installdependencies.sh

# Copy entrypoint script
COPY entrypoint.sh /runner/entrypoint.sh
RUN chmod +x /runner/entrypoint.sh

# Expose any ports if needed (none for basic runner)
# GitHub Actions runners typically don't need exposed ports

ENTRYPOINT ["/runner/entrypoint.sh"]