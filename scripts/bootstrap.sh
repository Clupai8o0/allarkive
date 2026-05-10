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

# Override from environment if set.
# On macOS, /var/lib/ is not user-writable; default to ~/allarkive-data instead.
if [[ -n "${ALLARKIVE_DATA_DIR:-}" ]]; then
    DATA_DIR="${ALLARKIVE_DATA_DIR}"
elif [[ "$(uname -s)" == "Darwin" ]]; then
    DATA_DIR="${HOME}/allarkive-data"
else
    DATA_DIR="/var/lib/allarkive"
fi
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

# ── Progress tracking ─────────────────────────────────────────────────────────

TOTAL_STEPS=7
STEP=0

# ── Terminal colors ────────────────────────────────────────────────────────────
# $'...' embeds the literal ESC byte so plain echo works without -e.
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
    R=$'\033[0m';  B=$'\033[1m';   DIM=$'\033[2m'
    CY=$'\033[36m';  BCY=$'\033[96m'
    GR=$'\033[32m';  BGR=$'\033[92m'
    YL=$'\033[93m';  RD=$'\033[91m';  WH=$'\033[97m'
else
    R=''; B=''; DIM=''; CY=''; BCY=''; GR=''; BGR=''; YL=''; RD=''; WH=''
fi

# ── Helper functions ──────────────────────────────────────────────────────────

info() { echo "  ${DIM}·${R}  $*"; }
warn() { echo "  ${YL}⚠${R}  $*" >&2; }
die()  { echo "  ${RD}✗  $*${R}" >&2; exit 1; }

step() {
    STEP=$((STEP + 1))
    local label="$*"
    local bar_width=50
    local filled=$(( STEP * bar_width / TOTAL_STEPS ))
    local pct=$(( STEP * 100 / TOTAL_STEPS ))
    local filled_bar='' empty_bar='' i=0
    while [[ $i -lt $filled ]];    do filled_bar+="█"; i=$((i+1)); done
    while [[ $i -lt $bar_width ]]; do empty_bar+="░"; i=$((i+1)); done
    echo ""
    echo "  ${CY}┌──────────────────────────────────────────────────────────────────${R}"
    echo "  ${CY}│${R}  ${B}▶  ${label}${R}  ${DIM}(${STEP}/${TOTAL_STEPS})${R}"
    echo "  ${CY}│${R}  ${BGR}${filled_bar}${DIM}${empty_bar}${R}  ${YL}${pct}%${R}"
    echo "  ${CY}└──────────────────────────────────────────────────────────────────${R}"
    echo ""
}

print_banner() {
    echo ""
    echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
    echo "  ${CY}║${R}"
    echo "  ${CY}║${R}  ${B}${WH}░▒▓  AllArkive  ▓▒░${R}   self-hosted knowledge ark"
    echo "  ${CY}║${R}"
    echo "  ${CY}║${R}  ${DIM}bundle : ${BUNDLE}${R}"
    echo "  ${CY}║${R}  ${DIM}data   : ${DATA_DIR}${R}"
    echo "  ${CY}║${R}"
    echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
    echo ""
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

# ── Banner ────────────────────────────────────────────────────────────────────

print_banner

# ── Step 1: Prerequisite checks ───────────────────────────────────────────────

step "Checking prerequisites"
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

step "Creating data directories"
info "Creating data directories under ${DATA_DIR}..."
mkdir -p "${DATA_DIR}/zim" \
         "${DATA_DIR}/models" \
         "${DATA_DIR}/index" \
         "${DATA_DIR}/data"
info "Directories OK."

# ── Step 3: .env file ─────────────────────────────────────────────────────────

step "Configuring environment"
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

step "Checking disk space"
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

step "Fetching bundle: ${BUNDLE}"
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

step "Starting Docker Compose stack"
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
            echo "  ${BGR}✓${R}  ${service}: healthy"
            return 0
        fi

        sleep "${interval}"
        elapsed=$((elapsed + interval))
        printf "  ${DIM}·${R}  waiting for %s  %ds / %ds...\r" "${service}" "${elapsed}" "${max_wait}"
    done

    warn "${service} did not become healthy within ${max_wait}s."
    warn "Check logs: docker compose -f ${COMPOSE_FILE} logs ${service}"
    return 1
}

wait_healthy ollama 120 || true
wait_healthy kiwix 60 || true

# ── Step 7: Pull models and index ─────────────────────────────────────────────

step "Pulling models and running RAG indexer"
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
BGR = '\033[92m'; DIM = '\033[2m'; YL = '\033[93m'; WH = '\033[97m'; R = '\033[0m'
BAR_W = 36
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
            pct = completed / total
            filled = int(pct * BAR_W)
            bar = f"{BGR}{'█'*filled}{DIM}{'░'*(BAR_W-filled)}{R}"
            print(f"\r    [{bar}]  {YL}{pct*100:.0f}%{R}  {status}", end="", flush=True)
        else:
            print(f"  {DIM}·{R}  {status}    ", flush=True)
    except json.JSONDecodeError:
        pass
print()
PYEOF

    echo "  ${BGR}✓${R}  Model pull complete: ${DEFAULT_MODEL}"
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
BGR = '\033[92m'; DIM = '\033[2m'; YL = '\033[93m'; WH = '\033[97m'; R = '\033[0m'
BAR_W = 36
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
            pct = completed / total
            filled = int(pct * BAR_W)
            bar = f"{BGR}{'█'*filled}{DIM}{'░'*(BAR_W-filled)}{R}"
            print(f"\r    [{bar}]  {YL}{pct*100:.0f}%{R}  {status}", end="", flush=True)
        else:
            print(f"  {DIM}·{R}  {status}    ", flush=True)
    except json.JSONDecodeError:
        pass
print()
PYEOF
    echo "  ${BGR}✓${R}  Embedding model pull complete: ${EMBED_MODEL}"
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
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${BGR}✓${R}  ${B}${WH}AllArkive is running${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}Archive  (kiwix)  ${R}${WH}http://127.0.0.1:${KIWIX_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}Chat     (WebUI)  ${R}${WH}http://127.0.0.1:${WEBUI_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}RAG      (API)    ${R}${WH}http://127.0.0.1:${RAG_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}Model    (Ollama) ${R}${WH}http://127.0.0.1:${OLLAMA_PORT}${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}ZIM files       : ${ZIM_COUNT} file(s) in ${DATA_DIR}/zim${R}"
echo "  ${CY}║${R}  ${DIM}Chat model      : ${DEFAULT_MODEL}${R}"
echo "  ${CY}║${R}  ${DIM}Embedding model : ${EMBED_MODEL}${R}"
echo "  ${CY}║${R}  ${DIM}Network         : localhost only — nothing exposed externally${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  Select ${WH}allarkive-rag${R} in Open WebUI to query with citations."
echo "  ${CY}║${R}  Re-index after adding ZIMs:"
echo "  ${CY}║${R}    ${DIM}docker compose -f ${COMPOSE_FILE} exec rag python indexer.py${R}"
echo "  ${CY}║${R}  Stop : ${DIM}docker compose -f ${COMPOSE_FILE} down${R}"
echo "  ${CY}║${R}  Logs : ${DIM}docker compose -f ${COMPOSE_FILE} logs -f${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${YL}⚠${R}  Responses can be wrong. ${B}Check the citations.${R}"
echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
echo ""
