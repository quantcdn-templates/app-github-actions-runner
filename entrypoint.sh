#!/bin/bash
set -euo pipefail

echo "[$(date +'%Y-%m-%d %H:%M:%S')] GitHub Actions Multi-Runner starting..."

# Required environment variables
GITHUB_ORG=${GITHUB_ORG:-}
GITHUB_TOKEN=${GITHUB_TOKEN:-}
GITHUB_PAT=${GITHUB_PAT:-}
RUNNER_NAME_BASE=${RUNNER_NAME:-"${QUANT_APP_NAME:-quant-runner}-$(shuf -i 1000-9999 -n 1)"}
# Auto-detect architecture and add to labels
ARCH=$(uname -m)
case $ARCH in
    x86_64) ARCH_LABEL="amd64" ;;
    aarch64) ARCH_LABEL="arm64" ;;
    *) ARCH_LABEL="$ARCH" ;;
esac
RUNNER_LABELS=${RUNNER_LABELS:-"quant-cloud,self-hosted,$ARCH_LABEL"}
RUNNER_COUNT=${RUNNER_COUNT:-1}

# Function to generate registration token from PAT (inspired by multi-runners)
pat2token() {
    local github_api_url="https://api.github.com"
    local endpoint="orgs/${GITHUB_ORG}/actions/runners/registration-token"
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Converting PAT to registration token..."
    
    local response=$(curl -s -X POST \
        -H "Accept: application/vnd.github.v3+json" \
        -H "Authorization: token ${GITHUB_PAT}" \
        "${github_api_url}/${endpoint}")
    
    # Use jq for robust JSON parsing
    local token=$(echo "$response" | jq -r '.token // empty' 2>/dev/null)
    
    if [ -n "$token" ] && [ "$token" != "null" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ✅ Successfully generated registration token from PAT"
        echo "$token"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] ❌ Failed to generate token from PAT. Response: $response"
        return 1
    fi
}

# Validate required environment variables
if [ -z "$GITHUB_ORG" ]; then
    echo "ERROR: GITHUB_ORG environment variable is required"
    echo "Set GITHUB_ORG to your GitHub organization or user name"
    echo "Example: GITHUB_ORG=mycompany or GITHUB_ORG=myusername"
    exit 1
fi

echo "[$(date +'%Y-%m-%d %H:%M:%S')] Organization: ${GITHUB_ORG}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Base runner name: ${RUNNER_NAME_BASE}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner labels: ${RUNNER_LABELS}"
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Number of runners: ${RUNNER_COUNT}"

# Array to track runner PIDs for cleanup
RUNNER_PIDS=()

# Function to start a single runner instance
start_runner() {
    local runner_id=$1
    local runner_name="${RUNNER_NAME_BASE}-${runner_id}"
    local runner_dir="/runner/instance-${runner_id}"
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting runner ${runner_id}: ${runner_name}"
    
    # Create runner instance directory
    mkdir -p "${runner_dir}"
    cd "${runner_dir}"
    
           # Copy shared binaries, scripts, and externals to runner directory
           cp -r /runner/bin "${runner_dir}/"
           cp -r /runner/externals "${runner_dir}/" 2>/dev/null || true
           cp /runner/config.sh "${runner_dir}/"
           cp /runner/run.sh "${runner_dir}/"
           cp /runner/*.template "${runner_dir}/" 2>/dev/null || true
           cp /runner/env.sh "${runner_dir}/" 2>/dev/null || true
           cp /runner/safe_sleep.sh "${runner_dir}/" 2>/dev/null || true
    
    # Check for persistent config for this runner instance
    local config_dir="/runner/.runner-config/instance-${runner_id}"
    if [ -d "${config_dir}" ] && [ -f "${config_dir}/.runner" ]; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Found existing config, restoring..."
        cp "${config_dir}/.runner" ./ 2>/dev/null || true
        cp "${config_dir}/.credentials"* ./ 2>/dev/null || true
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ Using existing configuration"
    else
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: No existing config found, registering..."
        
        # Get registration token (from PAT or direct token)
        local registration_token=""
        if [ -n "$GITHUB_PAT" ]; then
            registration_token=$(pat2token)
            if [ $? -ne 0 ]; then
                echo "ERROR: Failed to generate registration token from PAT"
                exit 1
            fi
        elif [ -n "$GITHUB_TOKEN" ]; then
            registration_token="$GITHUB_TOKEN"
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Using provided registration token"
        else
            echo "ERROR: Either GITHUB_PAT or GITHUB_TOKEN is required for runner registration"
            echo ""
            echo "Option 1 (Recommended): Set GITHUB_PAT with Personal Access Token"
            echo "  - More reliable for automation (longer expiry)"
            echo "  - Required permissions: organization_self_hosted_runners:write (for org-level runners)"
            echo ""
            echo "Option 2: Set GITHUB_TOKEN with registration token"  
            echo "  - Get from: https://github.com/${GITHUB_ORG}/settings/actions/runners/new"
            echo "  - Expires in 1 hour"
            exit 1
        fi

        # Register runner with GitHub
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Registering with GitHub..."
        ./config.sh \
            --url "https://github.com/${GITHUB_ORG}" \
            --token "${registration_token}" \
            --name "${runner_name}" \
            --labels "${RUNNER_LABELS}" \
            --work "_work" \
            --replace \
            --unattended

        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ Registered successfully!"

        # Save config to persistent storage
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Saving config to persistent storage..."
        mkdir -p "${config_dir}"
        cp .runner .credentials* "${config_dir}/" 2>/dev/null || true
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ Config saved"
    fi
    
           # Configure BuildKit for this runner instance
           echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Configuring BuildKit..."
           
           # Configure BuildKit for this runner instance (TCP only)
           if [ -n "${BUILDKIT_HOST:-}" ]; then
               echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Using BuildKit TCP: ${BUILDKIT_HOST}"
               
               # Set up environment variables for TCP BuildKit
               export DOCKER_HOST="${BUILDKIT_HOST}"
               export DOCKER_BUILDKIT=1
               export BUILDKIT_HOST="${BUILDKIT_HOST}"
               
               # Create .env file for TCP BuildKit (for workflows to inherit)
               cat > .env << EOF
DOCKER_HOST=${BUILDKIT_HOST}
DOCKER_BUILDKIT=1
BUILDKIT_HOST=${BUILDKIT_HOST}
EOF
               
               # Configure docker context to use TCP BuildKit
               /usr/bin/docker context create buildkit --docker "host=${BUILDKIT_HOST}" 2>/dev/null || true
               /usr/bin/docker context use buildkit 2>/dev/null || true
               
               # Wait for BuildKit to be ready
               echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Waiting for BuildKit to be ready..."
               for i in {1..30}; do
                   if /usr/bin/docker buildx create --driver remote --name "tcp-buildkit-${runner_id}" "${BUILDKIT_HOST}" --use 2>/dev/null; then
                       echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ BuildKit connection established"
                       break
                   else
                       echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Waiting for BuildKit... (attempt $i/30)"
                       sleep 2
                   fi
               done
               
               # Verify the builder is working
               if /usr/bin/docker buildx inspect "tcp-buildkit-${runner_id}" >/dev/null 2>&1; then
                   echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ TCP BuildKit builder ready"
                   # Set as default builder for all workflows
                   /usr/bin/docker buildx use "tcp-buildkit-${runner_id}"
               else
                   echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ❌ Failed to connect to BuildKit at ${BUILDKIT_HOST}"
                   exit 1
               fi
               
               echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ TCP BuildKit configured and set as default"
           else
               echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ❌ No BUILDKIT_HOST configured - TCP required for ECS"
               exit 1
           fi
           
           echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: ✅ BuildKit configured"
           
           # Start the runner in background with BuildKit environment
           echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Starting runner process..."
           # Export environment variables for the runner process and its child workflows
           DOCKER_HOST="$DOCKER_HOST" \
           DOCKER_BUILDKIT="$DOCKER_BUILDKIT" \
           BUILDKIT_HOST="$BUILDKIT_HOST" \
           ./run.sh &
           local runner_pid=$!
           RUNNER_PIDS+=($runner_pid)
           echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner ${runner_id}: Started with PID ${runner_pid}"
}

# Handle shutdown gracefully for all runners
cleanup() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] Shutting down all runners..."
    
    # Kill all runner processes
    for pid in "${RUNNER_PIDS[@]}"; do
        if kill -0 $pid 2>/dev/null; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Terminating runner process $pid..."
            kill -TERM $pid 2>/dev/null || true
        fi
    done
    
    # Wait a bit for graceful shutdown
    sleep 5
    
    # Force kill any remaining processes
    for pid in "${RUNNER_PIDS[@]}"; do
        if kill -0 $pid 2>/dev/null; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Force killing runner process $pid..."
            kill -KILL $pid 2>/dev/null || true
        fi
    done
    
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] All runners shut down"
    exit 0
}

trap cleanup SIGTERM SIGINT

# Start all runner instances
echo "[$(date +'%Y-%m-%d %H:%M:%S')] Starting ${RUNNER_COUNT} runner instances..."
for i in $(seq 1 $RUNNER_COUNT); do
    start_runner $i
done

echo "[$(date +'%Y-%m-%d %H:%M:%S')] All runners started. Monitoring processes..."

# Monitor all runner processes
while true; do
    all_running=true
    for pid in "${RUNNER_PIDS[@]}"; do
        if ! kill -0 $pid 2>/dev/null; then
            echo "[$(date +'%Y-%m-%d %H:%M:%S')] Runner process $pid has stopped"
            all_running=false
        fi
    done
    
    if ! $all_running; then
        echo "[$(date +'%Y-%m-%d %H:%M:%S')] One or more runners have stopped, exiting..."
        cleanup
    fi
    
    sleep 30
done