#!/usr/bin/env bash
# bootstrap.sh — first-run setup for AllArkive
#
# Usage:
#   scripts/bootstrap.sh [--bundle <name>] [--model <name>] [--pi]
#   scripts/bootstrap.sh                   # balanced bundle, default model
#   scripts/bootstrap.sh --bundle minimal  # minimal bundle (Pi-friendly)
#   scripts/bootstrap.sh --pi              # use docker-compose.pi.yml
#
# What it does:
#   1. Checks prerequisites (Docker, disk space, .env file)
#   2. Creates data directories
#   3. Fetches the requested bundle (default: balanced)
#   4. Starts the Docker Compose stack
#   5. Pulls the default AI model into Ollama
#   6. Prints a status summary
#
# Idempotent: safe to re-run. Already-present ZIMs and pulled models are skipped.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"

# ── Defaults ──────────────────────────────────────────────────────────────────

BUNDLE="balanced"
PI_MODE=false
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
SKIP_BUNDLE=false

# Override from environment if set
DATA_DIR="${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}"
DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-qwen2.5:7b}"
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $0 [--bundle <name>] [--model <name>] [--pi] [--skip-bundle]

  --bundle <name>   ZIM bundle to fetch: minimal, balanced, comprehensive
                    (default: balanced)
  --model <name>    Ollama model to pull (default: qwen2.5:7b)
  --pi              Use docker-compose.pi.yml (Raspberry Pi target)
  --skip-bundle     Start services without fetching ZIM files
                    (use if you already fetched a bundle)
  -h, --help        Show this message
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle)
            BUNDLE="${2:?--bundle requires an argument}"
            shift 2
            ;;
        --model)
            DEFAULT_MODEL="${2:?--model requires an argument}"
            shift 2
            ;;
        --pi)
            PI_MODE=true
            COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi.yml"
            DATA_DIR="${ALLARKIVE_DATA_DIR:-/mnt/ssd/allarkive}"
            shift
            ;;
        --skip-bundle)
            SKIP_BUNDLE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: unknown argument: $1" >&2
            usage
            ;;
    esac
done

# ── Helper functions ──────────────────────────────────────────────────────────

info()  { echo "[bootstrap] $*"; }
warn()  { echo "[bootstrap] WARN: $*" >&2; }
die()   { echo "[bootstrap] ERROR: $*" >&2; exit 1; }

check_cmd() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

# ── Step 1: Prerequisite checks ───────────────────────────────────────────────

info "Checking prerequisites..."

check_cmd docker
check_cmd curl
check_cmd sha256sum
check_cmd python3

# Docker Compose (plugin form)
if ! docker compose version > /dev/null 2>&1; then
    die "Docker Compose plugin not found. Install Docker Engine 24+ with the Compose plugin."
fi

DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")"
COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || echo "unknown")"
info "Docker Engine: ${DOCKER_VERSION}"
info "Docker Compose: ${COMPOSE_VERSION}"

# Check Docker daemon is running
if ! docker info > /dev/null 2>&1; then
    die "Docker daemon is not running. Start it and retry."
fi

# ── Step 2: Data directory setup ──────────────────────────────────────────────

info "Creating data directories under ${DATA_DIR}..."
mkdir -p "${DATA_DIR}/zim" \
         "${DATA_DIR}/models" \
         "${DATA_DIR}/index" \
         "${DATA_DIR}/data"
info "Directories OK."

# ── Step 3: .env file ─────────────────────────────────────────────────────────

ENV_FILE="${COMPOSE_DIR}/.env"
ENV_EXAMPLE="${COMPOSE_DIR}/.env.example"

if [[ ! -f "${ENV_FILE}" ]]; then
    info ".env not found — creating from .env.example..."
    cp "${ENV_EXAMPLE}" "${ENV_FILE}"
    info "Created ${ENV_FILE}."
    echo ""
    echo "  ACTION REQUIRED: set WEBUI_SECRET_KEY in ${ENV_FILE}"
    echo "  Generate a key with: openssl rand -hex 32"
    echo ""
fi

# Check WEBUI_SECRET_KEY is set (non-empty)
WEBUI_SECRET_KEY="${WEBUI_SECRET_KEY:-}"
if [[ -z "${WEBUI_SECRET_KEY}" ]]; then
    # Try to read it from the .env file
    if grep -qE '^WEBUI_SECRET_KEY=.+' "${ENV_FILE}" 2>/dev/null; then
        WEBUI_SECRET_KEY="$(grep -E '^WEBUI_SECRET_KEY=' "${ENV_FILE}" | cut -d= -f2-)"
    fi
fi

if [[ -z "${WEBUI_SECRET_KEY}" ]]; then
    echo ""
    echo "  WEBUI_SECRET_KEY is not set in ${ENV_FILE}."
    echo "  Generate one with: openssl rand -hex 32"
    echo "  Then add it to ${ENV_FILE} and re-run this script."
    echo ""
    die "WEBUI_SECRET_KEY is required."
fi

# ── Step 4: Disk space check ──────────────────────────────────────────────────

check_disk_space() {
    local required_gb="$1"
    local path="$2"
    local available_gb

    # df --output=avail is not POSIX; use awk for portability
    available_gb="$(df -P "${path}" | awk 'NR==2 {print int($4 / 1048576)}')"

    if [[ "${available_gb}" -lt "${required_gb}" ]]; then
        warn "Low disk space on ${path}: ${available_gb} GB available, ${required_gb} GB recommended for the ${BUNDLE} bundle."
        warn "Proceeding anyway — you can always fetch a smaller bundle with --bundle minimal."
    else
        info "Disk space OK: ${available_gb} GB available on $(df -P "${path}" | awk 'NR==2 {print $1}')."
    fi
}

REQUIRED_GB="$(python3 - "${REPO_ROOT}/bundles/${BUNDLE}/manifest.json" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
hw = data.get("hardware", {})
print(hw.get("min_free_disk_gb", 10))
PYEOF
)"

check_disk_space "${REQUIRED_GB}" "${DATA_DIR}"

# ── Step 5: Fetch bundle ───────────────────────────────────────────────────────

if [[ "${SKIP_BUNDLE}" == false ]]; then
    ZIM_COUNT="$(find "${DATA_DIR}/zim" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"

    if [[ "${ZIM_COUNT}" -gt 0 ]]; then
        info "Found ${ZIM_COUNT} ZIM file(s) in ${DATA_DIR}/zim. Verifying..."
        "${SCRIPT_DIR}/fetch-bundle.sh" "${BUNDLE}" --dest "${DATA_DIR}/zim"
    else
        info "No ZIM files found. Fetching bundle: ${BUNDLE}..."
        "${SCRIPT_DIR}/fetch-bundle.sh" "${BUNDLE}" --dest "${DATA_DIR}/zim"
    fi
else
    info "--skip-bundle set. Skipping ZIM download."
    ZIM_COUNT="$(find "${DATA_DIR}/zim" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"
    if [[ "${ZIM_COUNT}" -eq 0 ]]; then
        warn "No ZIM files found in ${DATA_DIR}/zim. kiwix-serve will fail to start."
        warn "Fetch a bundle first: scripts/fetch-bundle.sh ${BUNDLE}"
    fi
fi

# ── Step 6: Start the Compose stack ───────────────────────────────────────────

info "Starting Docker Compose stack (${COMPOSE_FILE})..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d

info "Stack started. Waiting for services to be healthy..."

wait_healthy() {
    local service="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    local interval=5

    while [[ "${elapsed}" -lt "${max_wait}" ]]; do
        local status
        status="$(docker compose -f "${COMPOSE_FILE}" ps --format json "${service}" 2>/dev/null \
                  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Health','unknown'))" \
                  2>/dev/null || echo "unknown")"

        if [[ "${status}" == "healthy" ]]; then
            info "${service}: healthy"
            return 0
        fi

        sleep "${interval}"
        elapsed=$((elapsed + interval))
        info "Waiting for ${service} (${elapsed}s / ${max_wait}s)..."
    done

    warn "${service} did not become healthy within ${max_wait}s."
    warn "Check logs: docker compose -f ${COMPOSE_FILE} logs ${service}"
    return 1
}

wait_healthy ollama 120 || true
wait_healthy kiwix 60 || true

# ── Step 7: Pull the default model ────────────────────────────────────────────

OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT:-11434}"

info "Pulling model: ${DEFAULT_MODEL}"
info "(This downloads model weights — may take several minutes.)"

if curl -sf "${OLLAMA_URL}/api/version" > /dev/null 2>&1; then
    # Use the Ollama pull API; stream progress to stdout
    curl -s "${OLLAMA_URL}/api/pull" \
         -H 'Content-Type: application/json' \
         -d "{\"name\": \"${DEFAULT_MODEL}\"}" \
         | python3 - "${DEFAULT_MODEL}" <<'PYEOF'
import json, sys

model = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        status = obj.get("status", "")
        completed = obj.get("completed", 0)
        total = obj.get("total", 0)
        if total:
            pct = int(100 * completed / total)
            print(f"\r  {status}: {pct}%", end="", flush=True)
        else:
            print(f"  {status}", flush=True)
    except json.JSONDecodeError:
        pass
print()
PYEOF

    info "Model pull complete: ${DEFAULT_MODEL}"
else
    warn "Ollama is not reachable at ${OLLAMA_URL}. Pull models manually after startup:"
    warn "  docker compose -f ${COMPOSE_FILE} exec ollama ollama pull ${DEFAULT_MODEL}"
    warn "  docker compose -f ${COMPOSE_FILE} exec ollama ollama pull ${EMBED_MODEL}"
fi

# ── Step 7b: Pull embedding model ─────────────────────────────────────────────

info "Pulling embedding model: ${EMBED_MODEL}"

if curl -sf "${OLLAMA_URL}/api/version" > /dev/null 2>&1; then
    curl -s "${OLLAMA_URL}/api/pull" \
         -H 'Content-Type: application/json' \
         -d "{\"name\": \"${EMBED_MODEL}\"}" \
         | python3 - "${EMBED_MODEL}" <<'PYEOF'
import json, sys
model = sys.argv[1]
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
        status = obj.get("status", "")
        completed = obj.get("completed", 0)
        total = obj.get("total", 0)
        if total:
            pct = int(100 * completed / total)
            print(f"\r  {status}: {pct}%", end="", flush=True)
        else:
            print(f"  {status}", flush=True)
    except json.JSONDecodeError:
        pass
print()
PYEOF
    info "Embedding model pull complete: ${EMBED_MODEL}"
fi

# ── Step 7c: Wait for RAG service, then run indexer ───────────────────────────

wait_healthy rag 60 || true

info "Running RAG indexer (indexes ZIM content for retrieval)..."
info "(This can take several minutes for large bundles.)"

if docker compose -f "${COMPOSE_FILE}" ps --format json rag 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('State',''))" \
        2>/dev/null | grep -q "running"; then
    docker compose -f "${COMPOSE_FILE}" exec rag \
        python indexer.py \
            --zim-dir /data \
            --index-dir /index \
            --ollama-url http://ollama:11434 \
    && info "Indexing complete." \
    || warn "Indexer returned an error — see logs above. Queries will return no-sources until indexing succeeds."
else
    warn "RAG container is not running — skipping indexer."
    warn "After the stack is healthy, index manually:"
    warn "  docker compose -f ${COMPOSE_FILE} exec rag python indexer.py"
fi

# ── Step 8: Summary ───────────────────────────────────────────────────────────

KIWIX_PORT="${KIWIX_PORT:-8081}"
WEBUI_PORT="${WEBUI_PORT:-3000}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
RAG_PORT="${RAG_PORT:-8000}"

ZIM_COUNT="$(find "${DATA_DIR}/zim" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"

echo ""
echo "══════════════════════════════════════════════════════════════════════════"
echo " AllArkive is running"
echo "══════════════════════════════════════════════════════════════════════════"
echo ""
echo "  Archive (kiwix):    http://127.0.0.1:${KIWIX_PORT}"
echo "  Chat (Open WebUI):  http://127.0.0.1:${WEBUI_PORT}"
echo "  RAG service:        http://127.0.0.1:${RAG_PORT}"
echo "  Model API (Ollama): http://127.0.0.1:${OLLAMA_PORT}"
echo ""
echo "  ZIM files: ${ZIM_COUNT} file(s) in ${DATA_DIR}/zim"
echo "  Chat model: ${DEFAULT_MODEL}"
echo "  Embedding model: ${EMBED_MODEL}"
echo "  Binding: localhost only (127.0.0.1) — nothing is exposed externally"
echo ""
echo "  Select 'allarkive-rag' in Open WebUI to query with citations."
echo "  Re-index after adding new ZIMs:"
echo "    docker compose -f ${COMPOSE_FILE} exec rag python indexer.py"
echo ""
echo "  To stop: docker compose -f ${COMPOSE_FILE} down"
echo "  To view logs: docker compose -f ${COMPOSE_FILE} logs -f"
echo ""
echo "  Responses can be wrong. Check the citations."
echo "══════════════════════════════════════════════════════════════════════════"
