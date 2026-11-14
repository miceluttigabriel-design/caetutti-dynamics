#!/usr/bin/env bash
# =============================================================================
# Caetutti Dynamics - Deploy Script (para actualizaciones posteriores)
# Uso: ./deploy.sh [--pull] [--rebuild] [--restart-all]
# =============================================================================

set -euo pipefail

PROJECT_DIR="/home/appuser/caetutti-dynamics"
PULL=false
REBUILD=false
RESTART_ALL=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --pull) PULL=true; shift ;;
        --rebuild) REBUILD=true; shift ;;
        --restart-all) RESTART_ALL=true; shift ;;
        *) echo "Uso: $0 [--pull] [--rebuild] [--restart-all]"; exit 1 ;;
    esac
done

cd "$PROJECT_DIR"

log() { echo -e "\033[0;32m[$(date '+%H:%M:%S')]\033[0m $*"; }
warn() { echo -e "\033[1;33m[$(date '+%H:%M:%S')] WARN:\033[0m $*"; }
error() { echo -e "\033[0;31m[$(date '+%H:%M:%S')] ERROR:\033[0m $*" >&2; }

if [[ "$PULL" == true ]]; then
    log "Pulling latest code..."
    git fetch origin
    git reset --hard origin/main
fi

if [[ "$REBUILD" == true ]]; then
    log "Building Docker images..."
    docker compose build --pull --no-cache
else
    log "Building Docker images (cached)..."
    docker compose build --pull
fi

if [[ "$RESTART_ALL" == true ]]; then
    log "Restarting all services..."
    docker compose down
    docker compose up -d
else
    log "Restarting changed services..."
    docker compose up -d
fi

# Wait for healthchecks
log "Waiting for healthchecks..."
sleep 10

# Verify
log "Verifying deployment..."
docker compose ps

curl -sf http://localhost:4000/api/health && echo " ✓ Backend OK" || echo " ✗ Backend FAIL"
curl -sf http://localhost:3000 >/dev/null && echo " ✓ Frontend OK" || echo " ✗ Frontend FAIL"
curl -sf http://localhost/healthz >/dev/null && echo " ✓ Nginx OK" || echo " ✗ Nginx FAIL"

log "Deploy completed!"