#!/usr/bin/env bash
# reindex.sh — rebuild the RAG vector index at a chosen depth level
#
# Usage:
#   scripts/reindex.sh                  # standard level (default)
#   scripts/reindex.sh --level quick    # fast, good for demos
#   scripts/reindex.sh --level standard # solid coverage, run overnight
#   scripts/reindex.sh --level full     # complete, no article cap
#   scripts/reindex.sh --force          # rebuild even if ZIMs are unchanged
#   scripts/reindex.sh --pi             # use Pi compose file
#
# Levels
# ──────
#   quick    Large ZIMs (≥ 4 GB) → 10 000 articles  │ Small ZIMs → unlimited
#            Est. 1–3 hours. Good enough for demos and sanity checks.
#
#   standard Large ZIMs (≥ 4 GB) → 100 000 articles │ Small ZIMs → unlimited
#            Est. 10–18 hours. Run overnight before the demo.
#
#   full     All ZIMs → unlimited (no article cap)
#            Est. days for large Wikipedia ZIMs. Maximum coverage.
#
# "Large" vs "small" is decided by ZIM file size (threshold: 4 GB).
# Stack Exchange, iFixit, WikiMed (typically < 4 GB) are always fully indexed.
# Wikipedia mini (~12 GB) is capped by level.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"

# ── Defaults ──────────────────────────────────────────────────────────────────

LEVEL="standard"
FORCE=false
COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"

LARGE_ZIM_GB=4        # ZIMs at or above this size are "large"

# Per-level article caps for large ZIMs (0 = unlimited)
CAP_QUICK=10000
CAP_STANDARD=100000
CAP_FULL=0

# ── Terminal colours ──────────────────────────────────────────────────────────

if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    CY=$'\033[36m'; BCY=$'\033[96m'
    GR=$'\033[32m'; BGR=$'\033[92m'
    YL=$'\033[93m'; WH=$'\033[97m'
else
    R=''; B=''; DIM=''; CY=''; BCY=''; GR=''; BGR=''; YL=''; WH=''
fi

info() { echo "  ${DIM}·${R}  $*"; }
warn() { echo "  ${YL}⚠${R}  $*" >&2; }
die()  { echo "  ${YL}✗  $*${R}" >&2; exit 1; }
ok()   { echo "  ${BGR}✓${R}  $*"; }

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $0 [options]

  --level quick|standard|full   Indexing depth (default: standard)
  --force                       Rebuild even if ZIMs are unchanged
  --pi                          Use docker-compose.pi.yml
  -h, --help                    Show this message

Levels:
  quick     large ZIMs → 10 000 articles,  small ZIMs → unlimited  (~1–3 h)
  standard  large ZIMs → 100 000 articles, small ZIMs → unlimited  (~10–18 h)
  full      all ZIMs   → unlimited                                  (days)

"Large" = ZIM file ≥ ${LARGE_ZIM_GB} GB.
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --level)
            LEVEL="${2:?--level requires quick|standard|full}"
            shift 2
            ;;
        --force) FORCE=true; shift ;;
        --pi)    COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi.yml"; shift ;;
        -h|--help) usage ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

case "${LEVEL}" in
    quick)    LARGE_MAX=${CAP_QUICK}    ;;
    standard) LARGE_MAX=${CAP_STANDARD} ;;
    full)     LARGE_MAX=${CAP_FULL}     ;;
    *) die "unknown level '${LEVEL}' — choose quick, standard, or full" ;;
esac

# ── Sanity checks ─────────────────────────────────────────────────────────────

ENV_FILE="${COMPOSE_DIR}/.env"

[[ -f "${COMPOSE_FILE}" ]] || die "compose file not found: ${COMPOSE_FILE}"
[[ -f "${ENV_FILE}" ]]     || die "${ENV_FILE} not found — run scripts/bootstrap.sh first"

if ! docker info > /dev/null 2>&1; then
    die "Docker daemon is not running."
fi

# Check the rag container is up
RAG_STATE="$(docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" \
    ps --format json rag 2>/dev/null \
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('State','stopped'))" \
    2>/dev/null || echo "stopped")"

if [[ "${RAG_STATE}" != "running" ]]; then
    die "RAG container is not running. Start the stack first: scripts/bootstrap.sh --skip-bundle"
fi

# ── Banner ────────────────────────────────────────────────────────────────────

echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${B}${WH}AllArkive — RAG reindex${R}"
echo "  ${CY}║${R}"
echo "  ${CY}║${R}  ${DIM}level  :${R}  ${B}${LEVEL}${R}"

if [[ "${LARGE_MAX}" -gt 0 ]]; then
    echo "  ${CY}║${R}  ${DIM}large  :${R}  ZIMs ≥ ${LARGE_ZIM_GB} GB → ${LARGE_MAX} articles (random sample)"
    echo "  ${CY}║${R}  ${DIM}small  :${R}  ZIMs < ${LARGE_ZIM_GB} GB → fully indexed"
else
    echo "  ${CY}║${R}  ${DIM}cap    :${R}  none — all ZIMs fully indexed"
fi

case "${LEVEL}" in
    quick)    echo "  ${CY}║${R}  ${DIM}est.   :${R}  1–3 hours" ;;
    standard) echo "  ${CY}║${R}  ${DIM}est.   :${R}  10–18 hours — run overnight" ;;
    full)     echo "  ${CY}║${R}  ${DIM}est.   :${R}  days for large Wikipedia ZIMs" ;;
esac

[[ "${FORCE}" == true ]] && \
    echo "  ${CY}║${R}  ${YL}--force: existing index will be wiped and rebuilt${R}"

echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
echo ""

# ── Show installed ZIMs and their classification ──────────────────────────────

info "Installed ZIMs:"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" \
    exec rag python3 - "${LARGE_ZIM_GB}" <<'PYEOF'
import os, sys
from pathlib import Path

threshold_gb = float(sys.argv[1])
zim_dir = Path(os.environ.get("ZIM_DIR", "/data"))

zims = sorted(zim_dir.glob("*.zim"))
if not zims:
    print("    (no ZIM files found)")
    sys.exit(0)

for z in zims:
    size_gb = z.stat().st_size / 1e9
    tag = "large" if size_gb >= threshold_gb else "small → fully indexed"
    print(f"    {z.name:<55} {size_gb:>5.1f} GB  [{tag}]")
PYEOF

echo ""

# ── Run the indexer ───────────────────────────────────────────────────────────

FORCE_FLAG=""
[[ "${FORCE}" == true ]] && FORCE_FLAG="--force"

OLLAMA_BASE_URL="$(grep -E '^OLLAMA_BASE_URL=' "${ENV_FILE}" | cut -d= -f2- || true)"
OLLAMA_BASE_URL="${OLLAMA_BASE_URL:-http://ollama:11434}"

info "Starting indexer (level=${LEVEL}, large-zim-gb=${LARGE_ZIM_GB}, large-max-articles=${LARGE_MAX})..."
info "Logs stream below. This runs in the foreground — leave the terminal open."
echo ""

docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" exec rag \
    python indexer.py \
        --zim-dir    /data \
        --index-dir  /index \
        --ollama-url "${OLLAMA_BASE_URL}" \
        --large-zim-gb "${LARGE_ZIM_GB}" \
        --large-max-articles "${LARGE_MAX}" \
        ${FORCE_FLAG}

echo ""
ok "Indexing complete (level=${LEVEL})."
info "Restart or reload the RAG service if it was caching the old index:"
info "  docker compose -f ${COMPOSE_FILE} restart rag"
echo ""
