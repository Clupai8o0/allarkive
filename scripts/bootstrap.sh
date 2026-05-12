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
#
# Implementation is split across scripts/lib/*.sh — this file orchestrates;
# the libs hold reusable helpers (UI, platform detection, env mutation, etc).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"
LIB_DIR="${SCRIPT_DIR}/lib"

# ── Defaults ──────────────────────────────────────────────────────────────────

# Platform: auto = detect from `uname` + /proc/device-tree/model. Override with
# --platform mac|linux|pi|wsl (or the back-compat --pi alias).
PLATFORM="auto"
SKIP_BUNDLE=false
KEEP_ENV=false
ASSUME_YES=false
NO_MODEL=false

# Bundle/model/article-cap start unset; per-platform defaults (and an optional
# low-RAM override) fill them in unless the user passed --bundle / --model /
# --max-articles / --full-index explicitly.
BUNDLE=""
DEFAULT_MODEL=""
EMBED_MODEL="${EMBED_MODEL:-nomic-embed-text}"
MAX_ARTICLES=""        # per-ZIM article cap. 0 = unlimited.
BUNDLE_EXPLICIT=false
MODEL_EXPLICIT=false
MAX_ARTICLES_EXPLICIT=false

# Config file — persists per-subsystem storage paths between runs.
ALLARKIVE_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/allarkive"
ALLARKIVE_CONFIG="${ALLARKIVE_CONFIG_DIR}/config.json"

# Per-subsystem dir overrides from CLI (empty = not given this run).
ZIM_DIR_ARG=""
MODELS_DIR_ARG=""
INDEX_DIR_ARG=""

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $0 [options]

  --platform <name>   Target platform: auto, mac, linux, pi, wsl (default: auto)
                      auto detects from uname/proc. Sets compose file, data dir,
                      and default bundle/model unless overridden.
  --bundle <name>     ZIM bundle: minimal, balanced, comprehensive
                      (default: platform-dependent — minimal on Pi/low-RAM, else balanced)
  --model <name>      Ollama chat model to pull
                      (default: platform-dependent — qwen2.5:1.5b on Pi, qwen2.5:7b otherwise)
  --pi                Alias for --platform pi. Kept for back-compat.
  --no-model          Search-only mode: skip the chat-model pull. The embedding
                      model is still pulled (indexing needs it). RAG queries
                      return retrieved passages with citations, no LLM
                      summarisation. Landing page hides the "Ask AI" UI.
  --max-articles <N>  Per-ZIM article cap for the indexer. 0 = unlimited (index
                      every article). Higher values = better RAG coverage but
                      longer indexing. Defaults vary by platform: 3000 on Pi,
                      0 (unlimited) elsewhere. Without this flag, the
                      platform default is used.
  --full-index        Alias for --max-articles 0. Index every article in every
                      ZIM. On a Pi with the comprehensive bundle this is days
                      of indexing; on Apple Silicon / NVIDIA it's hours.
  --skip-bundle       Skip ZIM fetch (use existing files)
  --keep-env          Use ports exactly as set in compose/.env — no auto-adjustment.
                      Without this flag, ports reset to defaults (8080/8081/3000/…)
                      on every run and only increment if those defaults are occupied.
  --yes, -y           Skip the platform-summary confirmation prompt (for CI / scripts).
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
        --bundle)      BUNDLE="${2:?--bundle requires an argument}"; BUNDLE_EXPLICIT=true; shift 2 ;;
        --model)       DEFAULT_MODEL="${2:?--model requires an argument}"; MODEL_EXPLICIT=true; shift 2 ;;
        --platform)    PLATFORM="${2:?--platform requires an argument}"; shift 2 ;;
        --pi)          PLATFORM="pi"; shift ;;
        --no-model)    NO_MODEL=true; shift ;;
        --max-articles)
            MAX_ARTICLES="${2:?--max-articles requires an argument}"
            MAX_ARTICLES_EXPLICIT=true
            shift 2 ;;
        --full-index)  MAX_ARTICLES=0; MAX_ARTICLES_EXPLICIT=true; shift ;;
        --skip-bundle) SKIP_BUNDLE=true; shift ;;
        --keep-env)    KEEP_ENV=true; shift ;;
        --yes|-y)      ASSUME_YES=true; shift ;;
        --zim-dir)     ZIM_DIR_ARG="${2:?--zim-dir requires an argument}"; shift 2 ;;
        --models-dir)  MODELS_DIR_ARG="${2:?--models-dir requires an argument}"; shift 2 ;;
        --index-dir)   INDEX_DIR_ARG="${2:?--index-dir requires an argument}"; shift 2 ;;
        -h|--help)     usage ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

# ── Source helper libraries ───────────────────────────────────────────────────

# shellcheck source=lib/platform.sh
. "${LIB_DIR}/platform.sh"
# shellcheck source=lib/config.sh
. "${LIB_DIR}/config.sh"
# shellcheck source=lib/env-file.sh
. "${LIB_DIR}/env-file.sh"
# shellcheck source=lib/checks.sh
. "${LIB_DIR}/checks.sh"
# shellcheck source=lib/models.sh
. "${LIB_DIR}/models.sh"

# ── Platform detection + profile ──────────────────────────────────────────────

if [[ "${PLATFORM}" == "auto" ]]; then
    PLATFORM="$(_detect_platform)"
    PLATFORM_AUTO=true
else
    PLATFORM_AUTO=false
fi

case "${PLATFORM}" in
    mac|linux|pi|wsl) ;;
    *) echo "ERROR: unknown --platform: ${PLATFORM} (expected: auto, mac, linux, pi, wsl)" >&2; exit 1 ;;
esac

# Per-platform compose file, data dir base, default bundle/model, and
# default per-ZIM article cap. The cap is the single biggest knob on RAG
# coverage: it bounds how many articles per ZIM get embedded. Pi defaults to
# a conservative cap to keep CPU-bound indexing tractable; everywhere else
# defaults to unlimited because GPU/Metal acceleration makes full coverage
# feasible and partial coverage has bitten the demo (article not in the
# random sample → "no sources found").
case "${PLATFORM}" in
    pi)
        COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi.yml"
        DATA_DIR="${ALLARKIVE_DATA_DIR:-/mnt/ssd/allarkive}"
        PLATFORM_DEFAULT_BUNDLE="minimal"
        PLATFORM_DEFAULT_MODEL="qwen2.5:1.5b"
        PLATFORM_DEFAULT_MAX_ARTICLES=3000
        ;;
    mac)
        COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
        DATA_DIR="${ALLARKIVE_DATA_DIR:-${HOME}/allarkive-data}"
        PLATFORM_DEFAULT_BUNDLE="balanced"
        PLATFORM_DEFAULT_MODEL="qwen2.5:7b"
        PLATFORM_DEFAULT_MAX_ARTICLES=0
        ;;
    wsl)
        COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
        DATA_DIR="${ALLARKIVE_DATA_DIR:-${HOME}/allarkive-data}"
        PLATFORM_DEFAULT_BUNDLE="balanced"
        PLATFORM_DEFAULT_MODEL="qwen2.5:7b"
        PLATFORM_DEFAULT_MAX_ARTICLES=0
        ;;
    linux|*)
        COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
        DATA_DIR="${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}"
        PLATFORM_DEFAULT_BUNDLE="balanced"
        PLATFORM_DEFAULT_MODEL="qwen2.5:7b"
        PLATFORM_DEFAULT_MAX_ARTICLES=0
        ;;
esac

# Low-RAM auto-downgrade. Only fires when the user didn't pin a bundle/model.
TOTAL_RAM_GB="$(_detect_ram_gb)"
RAM_DOWNGRADED=false
if [[ "${TOTAL_RAM_GB}" -gt 0 && "${TOTAL_RAM_GB}" -lt 6 ]]; then
    if [[ "${BUNDLE_EXPLICIT}" == false ]]; then
        PLATFORM_DEFAULT_BUNDLE="minimal"
        RAM_DOWNGRADED=true
    fi
    if [[ "${MODEL_EXPLICIT}" == false ]]; then
        PLATFORM_DEFAULT_MODEL="qwen2.5:1.5b"
        RAM_DOWNGRADED=true
    fi
fi

# Fill bundle/model/cap from the resolved platform profile.
[[ "${BUNDLE_EXPLICIT}" == false ]]       && BUNDLE="${PLATFORM_DEFAULT_BUNDLE}"
[[ "${MODEL_EXPLICIT}"  == false ]]       && DEFAULT_MODEL="${PLATFORM_DEFAULT_MODEL}"
[[ "${MAX_ARTICLES_EXPLICIT}" == false ]] && MAX_ARTICLES="${PLATFORM_DEFAULT_MAX_ARTICLES}"
DEFAULT_MODEL="${OLLAMA_DEFAULT_MODEL:-${DEFAULT_MODEL}}"

DETECTED_GPU="$(_detect_gpu)"
DOCKER_RAM_GB="$(_detect_docker_ram_gb)"

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

# ── Progress tracking + UI ────────────────────────────────────────────────────
# Source UI after PLATFORM/BUNDLE/etc are set so the banner prints correctly.

TOTAL_STEPS=7
STEP=0
ZIM_DIR_OK=true  # Set in step 2; gates ZIM operations in steps 4 and 5.

# shellcheck source=lib/ui.sh
. "${LIB_DIR}/ui.sh"

# ── Confirmation prompt ───────────────────────────────────────────────────────
# Show the user what was detected and what defaults will be used. Skipped when
# --yes is passed, stdin is not a TTY, or the user pinned the platform explicitly.

if [[ "${ASSUME_YES}" == false && "${PLATFORM_AUTO}" == true && -t 0 ]]; then
    echo ""
    echo "  ┌─ AllArkive bootstrap — detected platform ───────────────────────"
    echo "  │  platform : ${PLATFORM}    (uname=$(uname -s)/$(uname -m))"
    echo "  │  RAM      : ${TOTAL_RAM_GB} GB total"
    if [[ "${PLATFORM}" == "mac" || "${PLATFORM}" == "wsl" ]] && [[ "${DOCKER_RAM_GB}" -gt 0 ]]; then
        echo "  │  Docker   : ${DOCKER_RAM_GB} GB allocated to Docker Desktop"
    fi
    echo "  │  GPU      : ${DETECTED_GPU}"
    echo "  │  compose  : $(basename "${COMPOSE_FILE}")"
    echo "  │  data dir : ${DATA_DIR}"
    echo "  │  bundle   : ${BUNDLE}$([[ "${BUNDLE_EXPLICIT}" == true ]] && echo '  (explicit)' || echo '  (default)')"
    if [[ "${NO_MODEL}" == true ]]; then
        echo "  │  model    : (none — search-only mode)"
    else
        echo "  │  model    : ${DEFAULT_MODEL}$([[ "${MODEL_EXPLICIT}" == true ]] && echo '  (explicit)' || echo '  (default)')"
    fi
    if [[ "${MAX_ARTICLES}" -eq 0 ]]; then
        _cap_label="unlimited (index every article)"
    else
        _cap_label="${MAX_ARTICLES} per ZIM"
    fi
    echo "  │  index cap: ${_cap_label}$([[ "${MAX_ARTICLES_EXPLICIT}" == true ]] && echo '  (explicit)' || echo '  (default)')"
    if [[ "${RAM_DOWNGRADED}" == true ]]; then
        echo "  │  ⚠  low RAM (<6 GB) — auto-downgraded to minimal bundle + 1.5b model"
    fi
    if [[ "${PLATFORM}" == "mac" ]] && [[ "${DOCKER_RAM_GB}" -gt 0 ]] && [[ "${DOCKER_RAM_GB}" -lt 8 ]]; then
        echo "  │  ⚠  Docker Desktop has <8 GB allocated — bump in Settings → Resources"
    fi
    if [[ "${PLATFORM}" == "mac" ]]; then
        echo "  │  tip: install Ollama natively (brew install ollama) for Metal speedup"
    fi
    # WSL2 without an NVIDIA GPU = CPU-only Ollama. Indexing the balanced
    # bundle takes hours on CPU; warn early so the user can pick --bundle minimal
    # or set up nvidia-container-toolkit before walking away from the laptop.
    if [[ "${PLATFORM}" == "wsl" ]] && [[ "${DETECTED_GPU}" == "none" ]]; then
        echo "  │  ⚠  WSL2 + no NVIDIA GPU detected — Ollama will run on CPU."
        echo "  │     Indexing the balanced bundle will take hours. Consider --bundle minimal,"
        echo "  │     or install nvidia-container-toolkit inside WSL2 to enable GPU passthrough."
    fi
    echo "  └─────────────────────────────────────────────────────────────────"
    echo ""
    read -r -p "  Continue with these settings? [Y/n] " _CONFIRM
    case "${_CONFIRM:-y}" in
        n|N|no|NO|No) echo "  Aborted."; exit 0 ;;
    esac
    echo ""
fi

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

# ── Step 3: .env file + ports + ollama detection ──────────────────────────────

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
# RAG_MAX_ARTICLES seeds the indexer's --max-articles default. Keeping it in
# .env means manual `docker compose exec rag python indexer.py` runs honour
# the same cap the user picked at bootstrap time.
_env_set RAG_MAX_ARTICLES     "${MAX_ARTICLES}" "${ENV_FILE}"
info "Storage paths written to ${ENV_FILE}."

# Release AllArkive ports before checking availability so re-runs don't
# increment ports that are only held by our own previous containers.
info "Releasing previous AllArkive stack (if running)..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down 2>/dev/null || true

# Detect port conflicts and auto-assign free alternatives.
info "Checking ports..."
LANDING_PORT="$(_resolve_port LANDING_PORT 8080)"
KIWIX_PORT="$(_resolve_port   KIWIX_PORT   8081)"
OLLAMA_PORT="$(_resolve_port  OLLAMA_PORT  11434)"
WEBUI_PORT="$(_resolve_port   WEBUI_PORT   3000)"
RAG_PORT="$(_resolve_port     RAG_PORT     8000)"
info "Ports: landing=${LANDING_PORT}  kiwix=${KIWIX_PORT}  webui=${WEBUI_PORT}  rag=${RAG_PORT}  ollama=${OLLAMA_PORT}"

# Keep KIWIX_PUBLIC_URL and WEBUI_PUBLIC_URL in sync with the resolved ports
# so the RAG service returns the correct URLs to the landing page.
_env_set KIWIX_PUBLIC_URL "http://127.0.0.1:${KIWIX_PORT}"   "${ENV_FILE}"
_env_set WEBUI_PUBLIC_URL "http://127.0.0.1:${WEBUI_PORT}"   "${ENV_FILE}"

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
    # Apple Silicon: Docker-bound Ollama is CPU-only and much slower than
    # native Ollama using Metal. Surface this once, only when relevant.
    if [[ "${PLATFORM}" == "mac" && "$(uname -m)" == "arm64" ]]; then
        warn "macOS detected with no host Ollama — Dockerized Ollama runs on CPU only."
        warn "  For 5–10× faster embeddings + chat, install native Ollama:"
        warn "    brew install ollama && ollama serve &"
        warn "    ollama pull ${DEFAULT_MODEL} && ollama pull ${EMBED_MODEL}"
        warn "  Then re-run this script; it will auto-detect and use the host instance."
    fi
fi

# ── Step 4: Disk space check ──────────────────────────────────────────────────

step "Checking disk space"

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

# ── Step 5: Fetch bundle ──────────────────────────────────────────────────────

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
# Always rebuild the rag image so edits to scripts/rag/*.py take effect.
# Cached layers make this fast (~5s) when nothing changed; otherwise it
# picks up the new source. Without this, `up` reuses any locally-tagged
# allarkive-rag:0.1.0 image even when the source files have been modified —
# a footgun that's silently shipped stale code in past sessions.
info "Rebuilding rag image (picks up any scripts/rag/ source changes)..."
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" build rag

if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
    info "Skipping Docker Ollama — using local Ollama on 127.0.0.1:11434."
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d \
        --scale ollama=0
else
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" up -d
fi

info "Stack started. Waiting for services to be healthy..."

# Only wait for Docker Ollama health if we're not using the local instance.
if [[ "${USE_LOCAL_OLLAMA}" == false ]]; then
    wait_healthy ollama 120 || true
fi
wait_healthy kiwix 60 || true

# ── Step 7: Pull models and index ─────────────────────────────────────────────

step "Pulling models and running RAG indexer"

_pull_model_init

info "(Model weights may take several minutes to download.)"
if [[ "${NO_MODEL}" == true ]]; then
    info "--no-model: skipping chat-model pull (search-only mode)."
    # Sentinel value tells server.py to skip Ollama /api/chat calls and return
    # raw retrieved passages instead. Compose has a default of qwen2.5:7b that
    # only applies if CHAT_MODEL is unset, so we must write a value here.
    _env_set CHAT_MODEL "__none__" "${ENV_FILE}"
else
    _pull_model "${DEFAULT_MODEL}"
    _env_set CHAT_MODEL "${DEFAULT_MODEL}" "${ENV_FILE}"
fi
_pull_model "${EMBED_MODEL}"

_pull_model_cleanup

# Wait for the RAG service, then run the indexer.
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
    if [[ "${MAX_ARTICLES}" -eq 0 ]]; then
        info "Index cap: unlimited (every article in every ZIM)."
    else
        info "Index cap: ${MAX_ARTICLES} articles per ZIM (use --full-index to remove)."
    fi
    docker compose -f "${COMPOSE_FILE}" exec rag \
        python indexer.py \
            --zim-dir /data \
            --index-dir /index \
            --ollama-url "${_INDEXER_OLLAMA_URL}" \
            --max-articles "${MAX_ARTICLES}" \
    && info "Indexing complete." \
    || warn "Indexer returned an error — see logs above. Queries will return no-sources until indexing succeeds."
else
    warn "RAG container is not running — skipping indexer."
    warn "After the stack is healthy, index manually:"
    warn "  docker compose -f ${COMPOSE_FILE} exec rag python indexer.py"
fi

# ── Step 8: Summary ───────────────────────────────────────────────────────────

LANDING_PORT="${LANDING_PORT:-8080}"
KIWIX_PORT="${KIWIX_PORT:-8081}"
WEBUI_PORT="${WEBUI_PORT:-3000}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"
RAG_PORT="${RAG_PORT:-8000}"

ZIM_COUNT="$(find "${ZIM_DIR}" -maxdepth 1 -name '*.zim' 2>/dev/null | wc -l)"

# Pull chunk counts per ZIM straight from index.db so the user can see whether
# every archive actually made it into the vector store (a fresh user hitting
# "no sources found" usually means an unindexed or empty-coverage ZIM).
_index_coverage_lines() {
    docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec -T rag \
        python3 -c "
import sqlite3
from pathlib import Path
p = '/index/index.db'
if not Path(p).exists():
    print('  (index not built yet)')
else:
    rows = sqlite3.connect(p).execute(
        'SELECT zim_name, COUNT(*) FROM chunks GROUP BY zim_name ORDER BY zim_name'
    ).fetchall()
    if not rows:
        print('  (index empty)')
    else:
        total = sum(n for _, n in rows)
        for name, n in rows:
            print(f'  {name[:44]:<44s} {n:>8,d} chunks')
        print(f'  {\"TOTAL\":<44s} {total:>8,d} chunks')
" 2>/dev/null
}

echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${BGR}✓${R}  ${B}${WH}AllArkive is running${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${B}Start here:${R}"
echo "  ${CY}║${R}  ${DIM}Landing  (entry point)  ${R}${WH}http://127.0.0.1:${LANDING_PORT}${R}"
echo "  ${CY}║${R}"
echo "  ${CY}║${R}  ${DIM}Other services (linked from the landing page):${R}"
echo "  ${CY}║${R}  ${DIM}Archive  (kiwix)        ${R}${WH}http://127.0.0.1:${KIWIX_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}Chat     (Open WebUI)   ${R}${WH}http://127.0.0.1:${WEBUI_PORT}${R}"
echo "  ${CY}║${R}  ${DIM}RAG      (API)          ${R}${WH}http://127.0.0.1:${RAG_PORT}${R}"
if [[ "${USE_LOCAL_OLLAMA}" == true ]]; then
    echo "  ${CY}║${R}  ${DIM}Model    (Ollama)      ${R}${WH}http://127.0.0.1:11434${R}  ${DIM}(local)${R}"
else
    echo "  ${CY}║${R}  ${DIM}Model    (Ollama)      ${R}${WH}http://127.0.0.1:${OLLAMA_PORT}${R}"
fi
echo "  ${CY}║${R}"
if [[ "${LANDING_PORT}" != "8080" || "${KIWIX_PORT}" != "8081" ]]; then
    echo "  ${CY}║${R}  ${YL}Note:${R} ports were auto-adjusted to avoid conflicts."
    echo "  ${CY}║${R}  ${DIM}Defaults are landing=8080, archive=8081. Edit compose/.env to fix.${R}"
fi
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}ZIM files       : ${ZIM_COUNT} file(s)${R}"
echo "  ${CY}║${R}  ${DIM}ZIM dir         : ${ZIM_DIR}${R}"
echo "  ${CY}║${R}  ${DIM}Models dir      : ${MODELS_DIR}${R}"
echo "  ${CY}║${R}  ${DIM}Chat model      : ${DEFAULT_MODEL}${R}"
echo "  ${CY}║${R}  ${DIM}Embedding model : ${EMBED_MODEL}${R}"
echo "  ${CY}║${R}  ${DIM}Network         : localhost only — nothing exposed externally${R}"
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}Knowledge indexed (chunks per archive):${R}"
while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    echo "  ${CY}║${R}  ${DIM}${line}${R}"
done < <(_index_coverage_lines)
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
