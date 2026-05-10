#!/usr/bin/env bash
# bootstrap.sh — first-run setup for AllArkive
#
# Usage:
#   scripts/bootstrap.sh [--bundle <name>] [--model <name>] [--pi]
#   scripts/bootstrap.sh                              # balanced bundle, default model
#   scripts/bootstrap.sh --bundle minimal             # minimal bundle (Pi-friendly)
#   scripts/bootstrap.sh --pi                         # use docker-compose.pi.yml
#   scripts/bootstrap.sh --zim-dir /Volumes/SSD/zim  # ZIMs on external disk
#   scripts/bootstrap.sh --models-dir ~/big/models   # models elsewhere
#
# Storage paths passed via --zim-dir / --models-dir / --index-dir are saved to
# ~/.config/allarkive/config.json and reused on future runs automatically.
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

# Config file — persists per-subsystem storage paths between runs.
ALLARKIVE_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/allarkive"
ALLARKIVE_CONFIG="${ALLARKIVE_CONFIG_DIR}/config.json"

# Per-subsystem dir overrides from CLI (empty = not given this run).
ZIM_DIR_ARG=""
MODELS_DIR_ARG=""
INDEX_DIR_ARG=""

# Data root: used as the fallback base when no per-subsystem dir is configured.
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
Usage: $0 [options]

  --bundle <name>     ZIM bundle: minimal, balanced, comprehensive (default: balanced)
  --model <name>      Ollama model to pull (default: qwen2.5:7b)
  --pi                Use docker-compose.pi.yml (Raspberry Pi)
  --skip-bundle       Skip ZIM fetch (use existing files)
  --zim-dir <path>    Store ZIM files here — saved to config for future runs
  --models-dir <path> Store Ollama models here — saved to config for future runs
  --index-dir <path>  Store RAG index here — saved to config for future runs
  -h, --help          Show this message

Storage paths are persisted to ${ALLARKIVE_CONFIG_DIR}/config.json.
Edit that file directly to change paths without re-running bootstrap.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --bundle)      BUNDLE="${2:?--bundle requires an argument}"; shift 2 ;;
        --model)       DEFAULT_MODEL="${2:?--model requires an argument}"; shift 2 ;;
        --pi)
            PI_MODE=true
            COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi.yml"
            DATA_DIR="${ALLARKIVE_DATA_DIR:-/mnt/ssd/allarkive}"
            shift ;;
        --skip-bundle) SKIP_BUNDLE=true; shift ;;
        --zim-dir)     ZIM_DIR_ARG="${2:?--zim-dir requires an argument}"; shift 2 ;;
        --models-dir)  MODELS_DIR_ARG="${2:?--models-dir requires an argument}"; shift 2 ;;
        --index-dir)   INDEX_DIR_ARG="${2:?--index-dir requires an argument}"; shift 2 ;;
        -h|--help)     usage ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

# ── Config file helpers ───────────────────────────────────────────────────────

_cfg_get() {
    # Prints the value for <key> from config.json, or empty string if absent.
    local key="$1"
    if [[ ! -f "${ALLARKIVE_CONFIG}" ]]; then
        echo ""; return 0
    fi
    python3 - "${ALLARKIVE_CONFIG}" "${key}" <<'PYEOF'
import json, sys, os
try:
    with open(sys.argv[1]) as f:
        val = json.load(f).get(sys.argv[2]) or ""
    print(os.path.expanduser(str(val)) if val else "")
except Exception:
    print("")
PYEOF
}

_cfg_save() {
    # Merge key=value pairs into config.json. Args: key val [key val ...]
    mkdir -p "${ALLARKIVE_CONFIG_DIR}"
    python3 - "${ALLARKIVE_CONFIG}" "$@" <<'PYEOF'
import json, sys
path, pairs = sys.argv[1], sys.argv[2:]
try:
    cfg = json.loads(open(path).read())
except Exception:
    cfg = {}
for i in range(0, len(pairs) - 1, 2):
    cfg[pairs[i]] = pairs[i + 1]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
}

# ── Resolve per-subsystem storage paths ──────────────────────────────────────
# Priority: CLI arg → env var → config.json → DATA_DIR/subdir default.

ZIM_DIR="${ZIM_DIR_ARG:-${ALLARKIVE_ZIM_DIR:-$(_cfg_get zim_dir)}}"
ZIM_DIR="${ZIM_DIR:-${DATA_DIR}/zim}"

MODELS_DIR="${MODELS_DIR_ARG:-${ALLARKIVE_MODELS_DIR:-$(_cfg_get models_dir)}}"
MODELS_DIR="${MODELS_DIR:-${DATA_DIR}/models}"

INDEX_DIR="${INDEX_DIR_ARG:-${ALLARKIVE_INDEX_DIR:-$(_cfg_get index_dir)}}"
INDEX_DIR="${INDEX_DIR:-${DATA_DIR}/index}"

WEBUI_DATA_DIR="${DATA_DIR}/data"

# Persist any CLI-specified dirs to config for future runs.
_SAVE_ARGS=()
[[ -n "${ZIM_DIR_ARG}" ]]    && _SAVE_ARGS+=(zim_dir    "${ZIM_DIR}")
[[ -n "${MODELS_DIR_ARG}" ]] && _SAVE_ARGS+=(models_dir "${MODELS_DIR}")
[[ -n "${INDEX_DIR_ARG}" ]]  && _SAVE_ARGS+=(index_dir  "${INDEX_DIR}")
if [[ "${#_SAVE_ARGS[@]}" -gt 0 ]]; then
    _cfg_save "${_SAVE_ARGS[@]}"
fi

# ── Progress tracking ─────────────────────────────────────────────────────────

TOTAL_STEPS=7
STEP=0

# Set in step 2; gates ZIM operations in steps 4 and 5.
ZIM_DIR_OK=true

# ── Terminal colors ────────────────────────────────────────────────────────────
# $'...' embeds the literal ESC byte so plain echo works without -e.
USE_TUI=false
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
    R=$'\033[0m';  B=$'\033[1m';   DIM=$'\033[2m'
    CY=$'\033[36m';  BCY=$'\033[96m'
    GR=$'\033[32m';  BGR=$'\033[92m'
    YL=$'\033[93m';  RD=$'\033[91m';  WH=$'\033[97m'
    if command -v tput > /dev/null 2>&1 && tput cup 0 0 > /dev/null 2>&1; then
        USE_TUI=true
    fi
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
    printf '\033[2J\033[H'
    print_banner
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
    echo "  ${CY}║${R}  ${DIM}zim    : ${ZIM_DIR}${R}"
    echo "  ${CY}║${R}  ${DIM}models : ${MODELS_DIR}${R}"
    echo "  ${CY}║${R}"
    echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
    echo ""
}

check_cmd() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

check_dir_accessible() {
    # Returns 0 if dir exists/is creatable and writable; 1 with warnings otherwise.
    local dir="$1" label="$2"
    if mkdir -p "${dir}" 2>/dev/null && [[ -w "${dir}" ]]; then
        return 0
    fi
    warn "${label} directory is not accessible: ${dir}"
    case "${dir}" in
        /Volumes/*|/mnt/*|/media/*)
            warn "This looks like an external disk path — is the disk mounted?" ;;
    esac
    warn "Config: ${ALLARKIVE_CONFIG}"
    return 1
}

_env_set() {
    # Set KEY=VALUE in an env file; updates in-place if key exists, appends if not.
    local key="$1" val="$2" file="$3"
    if grep -q "^${key}=" "${file}" 2>/dev/null; then
        python3 -c "
import sys; path, key, val = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(path).readlines()
open(path, 'w').write(''.join(f'{key}={val}\n' if l.startswith(key+'=') else l for l in lines))
" "${file}" "${key}" "${val}"
    else
        printf '\n%s=%s\n' "${key}" "${val}" >> "${file}"
    fi
}

_port_free() {
    # Check OS-level bind AND docker's port table (Docker Desktop on Mac doesn't
    # expose container ports as host sockets, so a plain bind() would miss them).
    python3 -c "
import socket, sys
port = int(sys.argv[1])
# Try binding — catches native processes and most Linux Docker setups.
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
try:
    s.bind(('127.0.0.1', port))
    s.close()
except OSError:
    sys.exit(1)
# Also try connecting — catches Docker Desktop port forwarder on macOS.
c = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
c.settimeout(0.3)
try:
    c.connect(('127.0.0.1', port))
    c.close()
    sys.exit(1)
except OSError:
    pass
sys.exit(0)
" "$1"
}

_ASSIGNED_PORTS=()

_resolve_port() {
    # Usage: PORT=$(_resolve_port VARNAME DEFAULT)
    # Reads current value from .env; bumps to next free port if in use or already
    # claimed by another service in this run; writes back.
    local varname="$1" default="$2"
    local preferred
    preferred="$(grep -E "^${varname}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true)"
    preferred="${preferred:-${default}}"
    local port="${preferred}"
    _already_assigned() {
        local p="$1" a
        for a in "${_ASSIGNED_PORTS[@]+"${_ASSIGNED_PORTS[@]}"}"; do
            [[ "$a" == "$p" ]] && return 0
        done
        return 1
    }
    while ! _port_free "${port}" || _already_assigned "${port}"; do
        port=$((port + 1))
    done
    if [[ "${port}" != "${preferred}" ]]; then
        warn "Port ${preferred} already in use — using ${port} for ${varname}."
    fi
    _ASSIGNED_PORTS+=("${port}")
    _env_set "${varname}" "${port}" "${ENV_FILE}"
    printf '%s' "${port}"
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

if ! docker compose version > /dev/null 2>&1; then
    die "Docker Compose plugin not found. Install Docker Engine 24+ with the Compose plugin."
fi

DOCKER_VERSION="$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "unknown")"
COMPOSE_VERSION="$(docker compose version --short 2>/dev/null || echo "unknown")"
info "Docker Engine: ${DOCKER_VERSION}"
info "Docker Compose: ${COMPOSE_VERSION}"

if ! docker info > /dev/null 2>&1; then
    die "Docker daemon is not running. Start it and retry."
fi

# ── Step 2: Data directory setup ──────────────────────────────────────────────

step "Creating data directories"

# ZIM dir may be on an external disk — use a non-fatal check.
if ! check_dir_accessible "${ZIM_DIR}" "ZIM"; then
    ZIM_DIR_OK=false
    warn "ZIM directory unavailable. Bundle fetch will be skipped this run."
    warn "Mount the disk and re-run, or pass --skip-bundle to start without ZIMs."
fi

mkdir -p "${MODELS_DIR}" "${INDEX_DIR}" "${WEBUI_DATA_DIR}"

if [[ "${ZIM_DIR_OK}" == true ]]; then
    info "ZIM     : ${ZIM_DIR}"
else
    info "ZIM     : ${ZIM_DIR}  ${YL}(not accessible)${R}"
fi
info "Models  : ${MODELS_DIR}"
info "Index   : ${INDEX_DIR}"
info "WebUI   : ${WEBUI_DATA_DIR}"
info "Config  : ${ALLARKIVE_CONFIG}"
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

# Write resolved storage paths into .env so docker compose uses them.
_env_set ALLARKIVE_ZIM_DIR    "${ZIM_DIR}"    "${ENV_FILE}"
_env_set ALLARKIVE_MODELS_DIR "${MODELS_DIR}" "${ENV_FILE}"
_env_set ALLARKIVE_INDEX_DIR  "${INDEX_DIR}"  "${ENV_FILE}"
_env_set ALLARKIVE_WEBUI_DIR  "${WEBUI_DATA_DIR}" "${ENV_FILE}"
info "Storage paths written to ${ENV_FILE}."

# Detect port conflicts and auto-assign free alternatives.
info "Checking ports..."
LANDING_PORT="$(_resolve_port LANDING_PORT 8080)"
KIWIX_PORT="$(_resolve_port   KIWIX_PORT   8081)"
OLLAMA_PORT="$(_resolve_port  OLLAMA_PORT  11434)"
WEBUI_PORT="$(_resolve_port   WEBUI_PORT   3000)"
RAG_PORT="$(_resolve_port     RAG_PORT     8000)"
info "Ports: landing=${LANDING_PORT}  kiwix=${KIWIX_PORT}  webui=${WEBUI_PORT}  rag=${RAG_PORT}  ollama=${OLLAMA_PORT}"

# Detect a locally-running Ollama and reuse it instead of starting a Docker container.
# On macOS with Docker Desktop, containers reach the host via host.docker.internal.
USE_LOCAL_OLLAMA=false
if curl -sf "http://127.0.0.1:11434/api/version" > /dev/null 2>&1; then
    warn "Local Ollama detected on port 11434 — using it instead of the Docker service."
    _env_set OLLAMA_BASE_URL "http://host.docker.internal:11434" "${ENV_FILE}"
    _env_set OLLAMA_URL      "http://host.docker.internal:11434" "${ENV_FILE}"
    USE_LOCAL_OLLAMA=true
    OLLAMA_URL="http://127.0.0.1:11434"
else
    _env_set OLLAMA_BASE_URL "http://ollama:11434" "${ENV_FILE}"
    _env_set OLLAMA_URL      "http://ollama:11434" "${ENV_FILE}"
    OLLAMA_URL="http://127.0.0.1:${OLLAMA_PORT}"
fi

# ── Step 4: Disk space check ──────────────────────────────────────────────────

step "Checking disk space"
check_disk_space() {
    local required_gb="$1"
    local path="$2"
    local available_gb
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
print(data.get("hardware", {}).get("min_free_disk_gb", 10))
PYEOF
)"

if [[ "${ZIM_DIR_OK}" == true ]]; then
    check_disk_space "${REQUIRED_GB}" "${ZIM_DIR}"
else
    info "Skipping ZIM disk space check — ZIM directory not accessible."
fi

# ── Step 5: Fetch bundle ───────────────────────────────────────────────────────

step "Fetching bundle: ${BUNDLE}"
if [[ "${SKIP_BUNDLE}" == false ]]; then
    if [[ "${ZIM_DIR_OK}" == false ]]; then
        warn "ZIM directory not accessible — skipping bundle fetch."
        warn "Mount the disk and re-run to download ZIM files."
        warn "Or use --skip-bundle to suppress this warning."
    else
        ZIM_COUNT="$(find "${ZIM_DIR}" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"
        if [[ "${ZIM_COUNT}" -gt 0 ]]; then
            info "Found ${ZIM_COUNT} ZIM file(s) in ${ZIM_DIR}. Verifying..."
        else
            info "No ZIM files found. Fetching bundle: ${BUNDLE}..."
        fi
        "${SCRIPT_DIR}/fetch-bundle.sh" "${BUNDLE}" --dest "${ZIM_DIR}"
    fi
else
    info "--skip-bundle set. Skipping ZIM download."
    ZIM_COUNT="$(find "${ZIM_DIR}" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"
    if [[ "${ZIM_DIR_OK}" == true ]] && [[ "${ZIM_COUNT}" -eq 0 ]]; then
        warn "No ZIM files found in ${ZIM_DIR}. kiwix-serve will fail to start."
        warn "Fetch a bundle first: scripts/fetch-bundle.sh ${BUNDLE}"
    fi
fi

# ── Step 6: Start the Compose stack ───────────────────────────────────────────

step "Starting Docker Compose stack"

info "Starting Docker Compose stack (${COMPOSE_FILE})..."
if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
    info "Skipping Docker Ollama — using local Ollama on 127.0.0.1:11434."
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d \
        --scale ollama=0
else
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
fi

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

# Only wait for Docker Ollama health if we're not using the local instance.
if [[ "${USE_LOCAL_OLLAMA}" == false ]]; then
    wait_healthy ollama 120 || true
fi
wait_healthy kiwix 60 || true

# ── Step 7: Pull models and index ─────────────────────────────────────────────

step "Pulling models and running RAG indexer"

# Write the pull-progress script to a temp file.
# Using `pipe | python3 - <<'PYEOF'` doesn't work: the heredoc takes python3's
# stdin, leaving the pipe with no reader and causing curl to exit with code 23.
_PULL_PY="$(mktemp)"
cat > "${_PULL_PY}" <<'PYEOF'
import json, sys
BGR = '\033[92m'; DIM = '\033[2m'; YL = '\033[93m'; WH = '\033[97m'; R = '\033[0m'
BAR_W = 36
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

_pull_model() {
    local model="$1"
    info "Pulling model: ${model}"
    if curl -sf "${OLLAMA_URL}/api/version" > /dev/null 2>&1; then
        curl -s "${OLLAMA_URL}/api/pull" \
             -H 'Content-Type: application/json' \
             -d "{\"name\": \"${model}\"}" \
             | python3 "${_PULL_PY}"
        echo "  ${BGR}✓${R}  Pull complete: ${model}"
    else
        warn "Ollama not reachable at ${OLLAMA_URL} — pull ${model} manually:"
        if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
            warn "  ollama pull ${model}"
        else
            warn "  docker compose -f ${COMPOSE_FILE} exec ollama ollama pull ${model}"
        fi
    fi
}

info "(Model weights may take several minutes to download.)"
_pull_model "${DEFAULT_MODEL}"

# ── Step 7b: Pull embedding model ─────────────────────────────────────────────

_pull_model "${EMBED_MODEL}"

rm -f "${_PULL_PY}"

# ── Step 7c: Wait for RAG service, then run indexer ───────────────────────────

wait_healthy rag 60 || true

info "Running RAG indexer (indexes ZIM content for retrieval)..."
info "(This can take several minutes for large bundles.)"

if docker compose -f "${COMPOSE_FILE}" ps --format json rag 2>/dev/null \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('State',''))" \
        2>/dev/null | grep -q "running"; then
    # Use host.docker.internal when Ollama is running natively on the host.
    if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
        _INDEXER_OLLAMA_URL="http://host.docker.internal:11434"
    else
        _INDEXER_OLLAMA_URL="http://ollama:11434"
    fi
    docker compose -f "${COMPOSE_FILE}" exec rag \
        python indexer.py \
            --zim-dir /data \
            --index-dir /index \
            --ollama-url "${_INDEXER_OLLAMA_URL}" \
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

ZIM_COUNT="$(find "${ZIM_DIR}" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"

echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${BGR}✓${R}  ${B}${WH}AllArkive is running${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}Archive  (kiwix)  ${R}${WH}http://127.0.0.1:${KIWIX_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}Chat     (WebUI)  ${R}${WH}http://127.0.0.1:${WEBUI_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}RAG      (API)    ${R}${WH}http://127.0.0.1:${RAG_PORT}${R}"
if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
    echo "  ${CY}║${R}  ${DIM}Model    (Ollama) ${R}${WH}http://127.0.0.1:11434${R}  ${DIM}(local)${R}"
else
    echo "  ${CY}║${R}  ${DIM}Model    (Ollama) ${R}${WH}http://127.0.0.1:${OLLAMA_PORT}${R}"
fi
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}ZIM files       : ${ZIM_COUNT} file(s)${R}"
echo "  ${CY}║${R}  ${DIM}ZIM dir         : ${ZIM_DIR}${R}"
echo "  ${CY}║${R}  ${DIM}Models dir      : ${MODELS_DIR}${R}"
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
