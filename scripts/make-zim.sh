#!/usr/bin/env bash
# make-zim.sh — turn a directory of your own documents into an AllArkive ZIM
#
# Converts arbitrary documents (markdown, docx, txt, html, …) into a single
# `.zim` file that kiwix-serve can host and the RAG indexer can ingest. Uses
# pandoc + zimwriterfs via pinned Docker images — nothing is installed on the
# host beyond Docker.
#
# Usage:
#   scripts/make-zim.sh --src <dir> --name <slug> --title "<title>" [options]
#
# Required:
#   --src <dir>           Directory containing your source documents.
#   --name <slug>         Output filename slug (becomes <slug>.zim).
#                         Lowercase letters, digits, and dashes only.
#   --title "<title>"     Human-readable title shown in Kiwix.
#
# Optional:
#   --description "<…>"   One-line description (default: same as --title).
#   --creator "<…>"       Author/creator name (default: current $USER).
#   --publisher "<…>"     Publisher (default: "self").
#   --language <code>     ISO 639-3 language code (default: eng).
#   --out <dir>           Where to write the .zim (default: ./out).
#   --welcome <file>      Welcome page relative to --src (default: index.html;
#                         auto-generated if absent).
#   --install             After building, copy the .zim into the ZIM dir and
#                         restart the kiwix container.
#   --reindex             Implies --install. Also runs scripts/reindex.sh so
#                         the new ZIM is searchable via the RAG layer.
#   --zim-dir <dir>       ZIM destination for --install (default: value of
#                         ALLARKIVE_ZIM_DIR env or /var/lib/allarkive/zim).
#   --help                Show this message.
#
# What it does:
#   1. Stages a working copy of --src into a temp directory.
#   2. Runs pandoc (Docker: pandoc/minimal) over any .md / .markdown / .rst /
#      .docx / .odt / .txt / .tex files, producing .html alongside them.
#   3. Generates a minimal index.html listing all HTML pages if none exists.
#   4. Runs zimwriterfs (Docker: ghcr.io/openzim/zim-tools) over the staged
#      directory and writes <slug>.zim to --out.
#   5. Reports the resulting file size and the sha256 of the .zim.
#   6. If --install / --reindex was passed, hands off to kiwix + reindex.sh.
#
# License reminder: anything you ZIM still carries its source license. If you
# plan to share or republish the .zim, check the licenses of the included docs.
# See docs/bundles/custom-docs.md.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Pinned Docker images (override via env if you must) ───────────────────────
PANDOC_IMAGE="${PANDOC_IMAGE:-pandoc/minimal:3.5.0}"
ZIMTOOLS_IMAGE="${ZIMTOOLS_IMAGE:-ghcr.io/openzim/zim-tools:3.4.2}"

# ── Defaults ──────────────────────────────────────────────────────────────────
SRC=""
NAME=""
TITLE=""
DESCRIPTION=""
CREATOR="${USER:-allarkive}"
PUBLISHER="self"
LANGUAGE="eng"
OUT_DIR="${REPO_ROOT}/out"
WELCOME="index.html"
DO_INSTALL=false
DO_REINDEX=false
ZIM_DIR="${ALLARKIVE_ZIM_DIR:-/var/lib/allarkive/zim}"

# ── Terminal colours ──────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    R=$'\033[0m'; B=$'\033[1m'; DIM=$'\033[2m'
    CY=$'\033[36m'; BGR=$'\033[92m'
    YL=$'\033[93m'; RD=$'\033[91m'; WH=$'\033[97m'
else
    R=''; B=''; DIM=''; CY=''; BGR=''; YL=''; RD=''; WH=''
fi

info() { echo "  ${DIM}·${R}  $*"; }
ok()   { echo "  ${BGR}✓${R}  $*"; }
warn() { echo "  ${YL}⚠${R}  $*" >&2; }
die()  { echo "  ${RD}✗  $*${R}" >&2; exit 1; }

usage() {
    sed -n '2,46p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit "${1:-1}"
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --src)         SRC="${2:?--src requires a directory}"; shift 2 ;;
        --name)        NAME="${2:?--name requires a slug}"; shift 2 ;;
        --title)       TITLE="${2:?--title requires a string}"; shift 2 ;;
        --description) DESCRIPTION="${2:?--description requires a string}"; shift 2 ;;
        --creator)     CREATOR="${2:?--creator requires a name}"; shift 2 ;;
        --publisher)   PUBLISHER="${2:?--publisher requires a name}"; shift 2 ;;
        --language)    LANGUAGE="${2:?--language requires an ISO 639-3 code}"; shift 2 ;;
        --out)         OUT_DIR="${2:?--out requires a directory}"; shift 2 ;;
        --welcome)     WELCOME="${2:?--welcome requires a filename}"; shift 2 ;;
        --zim-dir)     ZIM_DIR="${2:?--zim-dir requires a directory}"; shift 2 ;;
        --install)     DO_INSTALL=true; shift ;;
        --reindex)     DO_INSTALL=true; DO_REINDEX=true; shift ;;
        -h|--help)     usage 0 ;;
        *)             echo "ERROR: unknown argument: $1" >&2; usage 1 ;;
    esac
done

[[ -n "${SRC}"   ]] || die "missing --src <dir>"
[[ -n "${NAME}"  ]] || die "missing --name <slug>"
[[ -n "${TITLE}" ]] || die "missing --title \"<title>\""
[[ -d "${SRC}"   ]] || die "source directory not found: ${SRC}"

# Validate slug: lowercase, digits, dashes only.
if [[ ! "${NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    die "--name must be lowercase letters, digits, dashes (got: ${NAME})"
fi

DESCRIPTION="${DESCRIPTION:-${TITLE}}"
SRC_ABS="$(cd "${SRC}" && pwd)"
OUT_ABS="$(mkdir -p "${OUT_DIR}" && cd "${OUT_DIR}" && pwd)"

# ── Prerequisite checks ───────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || die "docker is required but not found in PATH"
docker info >/dev/null 2>&1       || die "Docker daemon is not running"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${B}${WH}AllArkive — make-zim${R}"
echo "  ${CY}║${R}  ${DIM}src   :${R}  ${SRC_ABS}"
echo "  ${CY}║${R}  ${DIM}name  :${R}  ${NAME}"
echo "  ${CY}║${R}  ${DIM}title :${R}  ${TITLE}"
echo "  ${CY}║${R}  ${DIM}out   :${R}  ${OUT_ABS}/${NAME}.zim"
echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
echo ""

# ── Stage source into a temp dir so we don't mutate the user's tree ───────────
STAGE="$(mktemp -d -t allarkive-zim-XXXXXX)"
cleanup() { rm -rf "${STAGE}"; }
trap cleanup EXIT INT TERM

info "Staging source into ${STAGE}"
# Preserve symlinks (-L would dereference); copy contents not the dir itself.
cp -R "${SRC_ABS}/." "${STAGE}/"

# ── Convert non-HTML documents via pandoc ─────────────────────────────────────
# We convert in-place: input.md → input.html, leaving the source alongside in
# case the user wants to see it inside the ZIM too.

CONVERTED=0
CONVERT_LIST="$(mktemp)"
# shellcheck disable=SC2016
find "${STAGE}" -type f \
    \( -iname '*.md' -o -iname '*.markdown' -o -iname '*.rst' \
       -o -iname '*.docx' -o -iname '*.odt' -o -iname '*.txt' -o -iname '*.tex' \) \
    > "${CONVERT_LIST}"

if [[ -s "${CONVERT_LIST}" ]]; then
    info "Pulling pandoc image (${PANDOC_IMAGE}) if missing..."
    docker pull --quiet "${PANDOC_IMAGE}" >/dev/null

    while IFS= read -r src_file; do
        rel="${src_file#"${STAGE}/"}"
        out_rel="${rel%.*}.html"
        out_file="${STAGE}/${out_rel}"
        # Skip if a hand-authored .html already exists next to it.
        if [[ -f "${out_file}" ]]; then
            continue
        fi
        info "  pandoc → ${rel}"
        # Mount the staged dir at /work; pandoc reads/writes inside it.
        docker run --rm \
            --user "$(id -u):$(id -g)" \
            -v "${STAGE}:/work" \
            -w /work \
            "${PANDOC_IMAGE}" \
            --standalone \
            --metadata "title=${rel}" \
            -o "${out_rel}" \
            "${rel}"
        CONVERTED=$((CONVERTED + 1))
    done < "${CONVERT_LIST}"
fi
rm -f "${CONVERT_LIST}"

if [[ "${CONVERTED}" -gt 0 ]]; then
    ok "Converted ${CONVERTED} document(s) to HTML."
else
    info "No documents needed conversion (source already HTML or empty)."
fi

# ── Auto-generate a welcome page if the user didn't provide one ──────────────
if [[ ! -f "${STAGE}/${WELCOME}" ]]; then
    info "No ${WELCOME} found — generating a contents page."
    {
        printf '<!doctype html>\n<html lang="en">\n<head>\n'
        printf '<meta charset="utf-8">\n<title>%s</title>\n' "${TITLE}"
        printf '<style>body{font:16px/1.5 system-ui,sans-serif;max-width:48rem;margin:2rem auto;padding:0 1rem}h1{margin-bottom:.2rem}p.meta{color:#666;margin-top:0}ul{padding-left:1.2rem}a{color:#0366d6;text-decoration:none}a:hover{text-decoration:underline}</style>\n'
        printf '</head>\n<body>\n<h1>%s</h1>\n' "${TITLE}"
        printf '<p class="meta">%s — by %s</p>\n' "${DESCRIPTION}" "${CREATOR}"
        printf '<ul>\n'
        # List every .html file (except the welcome itself) sorted by path.
        (cd "${STAGE}" && find . -type f -name '*.html' ! -path "./${WELCOME}" \
            | sed 's|^\./||' | LC_ALL=C sort) \
        | while IFS= read -r page; do
            label="${page%.html}"
            printf '<li><a href="%s">%s</a></li>\n' "${page}" "${label}"
        done
        printf '</ul>\n</body>\n</html>\n'
    } > "${STAGE}/${WELCOME}"
fi

# ── Build the ZIM via zimwriterfs ────────────────────────────────────────────
info "Pulling zim-tools image (${ZIMTOOLS_IMAGE}) if missing..."
docker pull --quiet "${ZIMTOOLS_IMAGE}" >/dev/null

OUT_FILE="${OUT_ABS}/${NAME}.zim"
TMP_OUT="${OUT_FILE}.part"
rm -f "${TMP_OUT}"

info "Building ${OUT_FILE} ..."
# zimwriterfs writes its output inside the container; mount OUT_ABS at /out.
docker run --rm \
    --user "$(id -u):$(id -g)" \
    -v "${STAGE}:/src:ro" \
    -v "${OUT_ABS}:/out" \
    "${ZIMTOOLS_IMAGE}" \
    zimwriterfs \
        --welcome="${WELCOME}" \
        --language="${LANGUAGE}" \
        --title="${TITLE}" \
        --description="${DESCRIPTION}" \
        --creator="${CREATOR}" \
        --publisher="${PUBLISHER}" \
        --name="${NAME}" \
        /src "/out/${NAME}.zim.part"

mv "${TMP_OUT}" "${OUT_FILE}"

# ── Report ────────────────────────────────────────────────────────────────────
SIZE="$(du -h "${OUT_FILE}" | cut -f1)"
SHA="$(shasum -a 256 "${OUT_FILE}" | awk '{print $1}')"

echo ""
ok "Built ${OUT_FILE} (${SIZE})"
info "sha256: ${SHA}"
echo ""

# ── Optional install + reindex ───────────────────────────────────────────────
if [[ "${DO_INSTALL}" == true ]]; then
    [[ -d "${ZIM_DIR}" ]] || mkdir -p "${ZIM_DIR}" 2>/dev/null \
        || die "cannot create ZIM dir: ${ZIM_DIR} (try sudo, or pass --zim-dir)"
    info "Copying into ${ZIM_DIR}/"
    cp "${OUT_FILE}" "${ZIM_DIR}/${NAME}.zim"
    ok "Installed: ${ZIM_DIR}/${NAME}.zim"

    if docker compose -f "${REPO_ROOT}/compose/docker-compose.yml" ps kiwix --format json 2>/dev/null | grep -q '"State":"running"'; then
        info "Restarting kiwix so it picks up the new ZIM..."
        docker compose -f "${REPO_ROOT}/compose/docker-compose.yml" restart kiwix >/dev/null
        ok "kiwix restarted."
    else
        warn "kiwix container is not running — start the stack to serve the ZIM."
    fi
fi

if [[ "${DO_REINDEX}" == true ]]; then
    info "Reindexing so the new content is searchable via RAG..."
    "${SCRIPT_DIR}/reindex.sh"
fi

echo ""
ok "Done."
info "Next: open kiwix at http://127.0.0.1:8081 and look for \"${TITLE}\"."
if [[ "${DO_REINDEX}" != true && "${DO_INSTALL}" == true ]]; then
    info "Re-run with --reindex (or run scripts/reindex.sh) to make it searchable via AI."
fi
echo ""
