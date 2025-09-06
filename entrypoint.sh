#!/bin/bash
set -euo pipefail

echo "[$(date +'%Y-%m-%d %H:%M:%S')] GitHub Actions Runner starting..."

# Required environment variables
GITHUB_ORG=${GITHUB_ORG:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
RUNNER_NAME=${RUNNER_NAME:-"${QUANT_APP_NAME:-quant-runner}-$(shuf -i 1000-9999 -n 1)"}
RUNNER_LABELS=${RUNNER_LABELS:-"quant-cloud,self-hosted"}

# Validate required environment variables
if [ -z "$GITHUB_ORG" ]; then
    echo "ERROR: GITHUB_ORG environment variable is required"
    echo "Set GITHUB_ORG to your GitHub organization or user name"
    echo "Example: GITHUB_ORG=mycompany or GITHUB_ORG=myusername"
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Organization: ${GITHUB_ORG}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner name: ${RUNNER_NAME}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner labels: ${RUNNER_LABELS}"

# Simple approach: Use existing config if available, otherwise register new
if [ -d .runner-config ] && [ -f .runner-config/.runner ]; then
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Found existing runner config, restoring..."
    # Copy all config files
    [ -f .runner-config/.runner ] && cp .runner-config/.runner . && echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restored .runner"
    [ -f .runner-config/.credentials ] && cp .runner-config/.credentials . && echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restored .credentials"
    [ -f .runner-config/.credentials_rsaparams ] && cp .runner-config/.credentials_rsaparams . && echo "[$(date +'%Y-%m-%d %H:%M:%S')] Restored .credentials_rsaparams"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ Using existing runner configuration"
else
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] No existing runner config found, registering new runner..."
    
    # Validate registration token 
    if [ -z "$GITHUB_TOKEN" ]; then
        echo "ERROR: GITHUB_TOKEN environment variable is required for initial registration"
        echo "Get a runner registration token from:"
        echo "https://github.com/${GITHUB_ORG}/settings/actions/runners/new"
        exit 1
    fi

    # Register new runner with GitHub
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Registering runner with GitHub..."
    ./config.sh \
        --url "https://github.com/${GITHUB_ORG}" \
        --token "${GITHUB_TOKEN}" \
        --name "${RUNNER_NAME}" \
        --labels "${RUNNER_LABELS}" \
        --work "_work" \
        --replace \
        --unattended

    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ Runner registered successfully!"

    # Save config to persistent storage
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Saving runner config to persistent storage..."
    mkdir -p .runner-config
    cp .runner .credentials* .runner-config/ 2>/dev/null || true
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ Config saved to persistent storage"
fi

# Handle shutdown gracefully
cleanup() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Shutting down runner..."
    if [[ -f .runner ]]; then
        # Only attempt deregistration if we have a token
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            ./config.sh remove --token "$GITHUB_TOKEN" 2>/dev/null || {
                echo "[$(date +'%Y-%m-%d %H:%M:%S')] Warning: Could not deregister runner (may already be removed)"
            }
        else
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Warning: No GITHUB_TOKEN provided for deregistration"
        fi
    fi
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start the runner
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting GitHub Actions runner..."
./run.sh &

# Wait for the runner process
wait $!