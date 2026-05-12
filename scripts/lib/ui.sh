# shellcheck shell=bash
# scripts/lib/ui.sh — terminal colours, status messages, step banner.
#
# Sourced by bootstrap.sh. Reads STEP / TOTAL_STEPS / PLATFORM / BUNDLE /
# DEFAULT_MODEL / ZIM_DIR / MODELS_DIR at call time (they're set in the parent).

# ── Terminal colours ──────────────────────────────────────────────────────────
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

# ── Status messages ───────────────────────────────────────────────────────────

info() { echo "  ${DIM}·${R}  $*"; }
warn() { echo "  ${YL}⚠${R}  $*" >&2; }
die()  { echo "  ${RD}✗  $*${R}" >&2; exit 1; }

# ── Banner + step progress ────────────────────────────────────────────────────

print_banner() {
    echo ""
    echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
    echo "  ${CY}║${R}"
    echo "  ${CY}║${R}  ${B}${WH}░▒▓  AllArkive  ▓▒░${R}   self-hosted knowledge ark"
    echo "  ${CY}║${R}"
    echo "  ${CY}║${R}  ${DIM}platform : ${PLATFORM}    bundle : ${BUNDLE}    model : ${DEFAULT_MODEL}${R}"
    echo "  ${CY}║${R}  ${DIM}zim    : ${ZIM_DIR}${R}"
    echo "  ${CY}║${R}  ${DIM}models : ${MODELS_DIR}${R}"
    echo "  ${CY}║${R}"
    echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
    echo ""
}

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
