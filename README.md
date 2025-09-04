# GitHub Actions Runner Template

A self-hosted GitHub Actions runner template for Quant Cloud, supporting both x86_64 and ARM64 architectures.

## Features

- **Multi-architecture support**: Both x86_64 and ARM64 variants
- **Secure**: Runs as non-root user with minimal privileges
- **Auto-configuration**: Automatically registers with GitHub
- **Graceful shutdown**: Properly deregisters runner on container stop
- **Docker support**: BuildKit rootless integration for secure container builds (Fargate-compatible)
- **Customizable**: Configure runner name, labels, and working directory

## Quick Start

### 1. Get GitHub Registration Token

1. Go to your GitHub organization or repository settings
2. Navigate to **Settings > Actions > Runners**
3. Click **New self-hosted runner**
4. Copy the registration token from the configuration commands

### 2. Set Environment Variables

```bash
export GITHUB_ORG="your-org-name"
export GITHUB_TOKEN="your-registration-token"
```

### 3. Run the Runner

**For x86_64:**
```bash
docker-compose up -d
```

**For ARM64:**
```bash
docker-compose -f docker-compose.arm64.yml up -d
```

**Note**: Both compose files now use the same unified Dockerfile with automatic architecture detection.

## Environment Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `GITHUB_ORG` | GitHub organization or username | `mycompany` or `myusername` |
| `GITHUB_TOKEN` | GitHub runner registration token | `ABCD1234...` |

### Optional

| Variable | Description | Default |
|----------|-------------|---------|
| `RUNNER_NAME` | Custom runner name | `quant-cloud-runner-{hostname}` |
| `RUNNER_LABELS` | Comma-separated labels | `quant-cloud,self-hosted` |
| `RUNNER_WORK_DIR` | Working directory for actions | `_work` |

## Usage Examples

### Basic Setup
```bash
docker run -d \
  -e GITHUB_ORG=mycompany \
  -e GITHUB_TOKEN=ABCD1234... \
  ghcr.io/quantcdn-templates/app-github-actions-runner:latest
```

### Custom Configuration
```bash
docker run -d \
  -e GITHUB_ORG=mycompany \
  -e GITHUB_TOKEN=ABCD1234... \
  -e RUNNER_NAME=my-custom-runner \
  -e RUNNER_LABELS=quant-cloud,self-hosted,gpu \
  ghcr.io/quantcdn-templates/app-github-actions-runner:latest
```

### With BuildKit Support (Fargate-compatible)
```bash
# Uses docker-compose with BuildKit sidecar
docker-compose up -d
# No Docker socket mounting required - uses BuildKit rootless
```

## Architecture Support

### Unified Multi-Architecture
- **Single `Dockerfile`** automatically detects target architecture
- **x86_64**: `ghcr.io/quantcdn-templates/app-github-actions-runner:latest`
- **ARM64**: `ghcr.io/quantcdn-templates/app-github-actions-runner:arm64`

## Security Considerations

1. **Registration tokens** are short-lived (1 hour) and single-use
2. **Personal Access Tokens** should have minimal scopes (only `repo` or `admin:org` for enterprise)
3. **Runner isolation**: Each runner runs in its own container
4. **Non-root execution**: Runner process runs as `actions-runner` user
5. **Docker builds**: Uses BuildKit rootless sidecar (no privileged containers or socket mounting)

## Troubleshooting

### Runner Not Appearing
- Check the registration token is valid and not expired
- Verify `GITHUB_ORG` matches your organization/username exactly
- Check container logs: `docker logs <container-name>`

### Permission Issues
- Check GitHub repository/organization access permissions
- For Docker builds, ensure BuildKit service is running (via docker-compose)

### Runner Offline
- Registration tokens expire after 1 hour
- Generate a new token and restart the container

## Getting Registration Tokens

### For Organizations
1. Go to `https://github.com/{ORG}/settings/actions/runners`
2. Click "New self-hosted runner"
3. Copy the token from the `--token` parameter

### For Personal Repositories
1. Go to `https://github.com/{USERNAME}/{REPO}/settings/actions/runners`
2. Click "New self-hosted runner"
3. Copy the token from the `--token` parameter

### Using GitHub CLI
```bash
# For organizations
gh api orgs/{ORG}/actions/runners/registration-token

# For repositories  
gh api repos/{OWNER}/{REPO}/actions/runners/registration-token
```

## Development

### Building Locally

**x86_64:**
```bash
docker build -t local-github-runner .
```

**Multi-platform:**
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t local-github-runner .
```

### Testing
```bash
# Test with fake token (will fail gracefully)
docker run --rm \
  -e GITHUB_ORG=test \
  -e GITHUB_TOKEN=test \
  local-github-runner
```

## Quant Cloud Deployment

When deploying to Quant Cloud:

1. Set `GITHUB_ORG` and `GITHUB_TOKEN` in your environment variables
2. The runner will automatically register and start processing jobs
3. Logs are available through Quant Cloud monitoring
4. The runner will gracefully shutdown and deregister when the container stops

## License

MIT License - see LICENSE file for details.