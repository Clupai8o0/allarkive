#!/usr/bin/env bash
# cleanup.sh — stop and optionally remove AllArkive data
#
# Usage:
#   scripts/cleanup.sh                  # stop containers only (safe, reversible)
#   scripts/cleanup.sh --images         # stop + remove Docker images
#   scripts/cleanup.sh --data           # stop + remove data dir (ZIMs, models, index)
#   scripts/cleanup.sh --all            # stop + remove images + remove data dir
#
# Nothing is deleted unless you pass --data or --all.
# --data and --all prompt for confirmation before deleting anything.
#
# What each level removes:
#   (default)   Containers are stopped and removed. Volumes, images, and data
#               on disk are untouched. Running `docker compose up -d` again
#               restarts everything instantly.
#   --images    Also removes pulled Docker images (kiwix-serve, ollama,
#               open-webui, nginx) and the locally-built RAG image.
#               Re-running the stack will re-pull and rebuild them.
#   --data      Also deletes the data directory ($ALLARKIVE_DATA_DIR).
#               This removes ZIM files, Ollama models, the RAG index, and the
#               Open WebUI database. Cannot be undone without re-downloading.
#   --all       Equivalent to --images + --data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"

# ── Defaults ──────────────────────────────────────────────────────────────────

REMOVE_IMAGES=false
REMOVE_DATA=false

if [[ "$(uname -s)" == "Darwin" ]]; then
    DATA_DIR="${ALLARKIVE_DATA_DIR:-${HOME}/allarkive-data}"
else
    DATA_DIR="${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}"
fi

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $0 [--images] [--data] [--all]

  (no flags)  Stop and remove containers only. Data and images are kept.
  --images    Also remove Docker images (requires re-pull on next start).
  --data      Also delete the data directory (ZIMs, models, index, WebUI DB).
              Prompts for confirmation. Cannot be undone.
  --all       --images + --data.
  -h, --help  Show this message.

Data directory: ${DATA_DIR}
  Override with: ALLARKIVE_DATA_DIR=/path/to/dir $0
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --images)
            REMOVE_IMAGES=true
            shift
            ;;
        --data)
            REMOVE_DATA=true
            shift
            ;;
        --all)
            REMOVE_IMAGES=true
            REMOVE_DATA=true
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

info() { echo "[cleanup] $*"; }
warn() { echo "[cleanup] WARN: $*" >&2; }

# ── Confirm destructive actions upfront ───────────────────────────────────────

if [[ "${REMOVE_DATA}" == true ]]; then
    echo ""
    echo "  WARNING: --data will permanently delete:"
    echo "    ${DATA_DIR}/zim/     (ZIM files — re-download required)"
    echo "    ${DATA_DIR}/models/  (Ollama models — re-download required)"
    echo "    ${DATA_DIR}/index/   (RAG index — re-indexing required)"
    echo "    ${DATA_DIR}/data/    (Open WebUI database — chat history lost)"
    echo ""
    read -r -p "  Type 'yes' to confirm: " CONFIRM
    if [[ "${CONFIRM}" != "yes" ]]; then
        echo "  Aborted."
        exit 0
    fi
    echo ""
fi

# ── Detect which compose file(s) to stop ─────────────────────────────────────

COMPOSE_FILES=()
for f in \
    "${COMPOSE_DIR}/docker-compose.yml" \
    "${COMPOSE_DIR}/docker-compose.pi.yml" \
    "${COMPOSE_DIR}/docker-compose.pi-archive.yml"
do
    if [[ -f "$f" ]]; then
        COMPOSE_FILES+=("$f")
    fi
done

ENV_FILE="${COMPOSE_DIR}/.env"

# ── Stop containers ───────────────────────────────────────────────────────────

info "Stopping AllArkive containers..."

for cf in "${COMPOSE_FILES[@]}"; do
    env_args=()
    if [[ -f "${ENV_FILE}" ]]; then
        env_args=(--env-file "${ENV_FILE}")
    fi

    if docker compose -f "${cf}" "${env_args[@]}" ps --quiet 2>/dev/null | grep -q .; then
        info "  Stopping: $(basename "${cf}")"
        docker compose -f "${cf}" "${env_args[@]}" down --remove-orphans
    fi
done

info "Containers stopped."

# ── Remove images ─────────────────────────────────────────────────────────────

if [[ "${REMOVE_IMAGES}" == true ]]; then
    info "Removing Docker images..."

    IMAGES=(
        "ghcr.io/kiwix/kiwix-serve:3.8.2"
        "ollama/ollama:0.22.1"
        "ghcr.io/open-webui/open-webui:0.9.2"
        "nginx:1.27.3-alpine"
        "allarkive-rag:0.1.0"
    )

    for img in "${IMAGES[@]}"; do
        if docker image inspect "${img}" > /dev/null 2>&1; then
            docker image rm "${img}" && info "  Removed: ${img}" || warn "  Could not remove: ${img}"
        else
            info "  Not present: ${img}"
        fi
    done

    info "Images removed."
fi

# ── Remove data directory ─────────────────────────────────────────────────────

if [[ "${REMOVE_DATA}" == true ]]; then
    info "Removing data directory: ${DATA_DIR}"

    if [[ ! -d "${DATA_DIR}" ]]; then
        info "  Data directory does not exist — nothing to delete."
    else
        rm -rf "${DATA_DIR}"
        info "  Deleted: ${DATA_DIR}"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════════"
echo " AllArkive cleanup complete"
echo "══════════════════════════════════════════════════════════════════════════"
echo ""
if [[ "${REMOVE_DATA}" == true ]]; then
    echo "  Data directory deleted. To start fresh:"
    echo "    ./scripts/bootstrap.sh --bundle balanced"
elif [[ "${REMOVE_IMAGES}" == true ]]; then
    echo "  Images removed. To restart (will re-pull images):"
    echo "    cd compose/ && docker compose up -d"
else
    echo "  Containers stopped. Data and images are intact."
    echo "  To restart: cd compose/ && docker compose up -d"
    echo "  To also remove images: $0 --images"
    echo "  To wipe everything:    $0 --all"
fi
echo ""
