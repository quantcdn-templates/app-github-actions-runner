#!/bin/bash
set -euo pipefail

echo "[$(date +'%Y-%m-%d %H:%M:%S')] GitHub Actions Runner starting..."

# Required environment variables
GITHUB_ORG=${GITHUB_ORG:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
RUNNER_NAME=${RUNNER_NAME:-"quant-cloud-runner-$(hostname)"}
RUNNER_LABELS=${RUNNER_LABELS:-"quant-cloud,self-hosted"}

# Validate required environment variables
if [ -z "$GITHUB_ORG" ]; then
    echo "ERROR: GITHUB_ORG environment variable is required"
    echo "Set GITHUB_ORG to your GitHub organization or user name"
    echo "Example: GITHUB_ORG=mycompany or GITHUB_ORG=myusername"
    exit 1
fi

if [ -z "$GITHUB_TOKEN" ]; then
    echo "ERROR: GITHUB_TOKEN environment variable is required"
    echo "Get a runner registration token from:"
    echo "https://github.com/${GITHUB_ORG}/settings/actions/runners/new"
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Configuring runner for organization: ${GITHUB_ORG}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner name: ${RUNNER_NAME}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner labels: ${RUNNER_LABELS}"

# Remove any existing runner configuration (for restarts)
if [ -f .runner ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Removing existing runner configuration..."
    ./config.sh remove --token "${GITHUB_TOKEN}" || true
fi

# Configure the runner
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Configuring GitHub Actions runner..."
./config.sh \
    --url "https://github.com/${GITHUB_ORG}" \
    --token "${GITHUB_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --work "_work" \
    --replace \
    --unattended

# Handle shutdown gracefully
cleanup() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Shutting down runner..."
    ./config.sh remove --token "${GITHUB_TOKEN}" || true
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start the runner
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting GitHub Actions runner..."
./run.sh &

# Wait for the runner process
wait $!