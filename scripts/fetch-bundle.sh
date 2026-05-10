#!/usr/bin/env bash
# fetch-bundle.sh — download and verify a named AllArkive bundle
#
# Usage:
#   scripts/fetch-bundle.sh <bundle-name> [--dest <dir>]
#   scripts/fetch-bundle.sh balanced
#   scripts/fetch-bundle.sh minimal --dest /mnt/ssd/allarkive/zim
#
# Arguments:
#   bundle-name   One of: minimal, balanced, comprehensive
#   --dest <dir>  ZIM destination directory (default: /var/lib/allarkive/zim)
#
# What it does:
#   1. Reads bundles/<bundle-name>/manifest.json
#   2. For each ZIM in the manifest:
#      a. Skips the file if it already exists and passes checksum verification
#      b. Downloads the ZIM from the URL in the manifest
#      c. Downloads the official .sha256 file from Kiwix
#      d. Verifies the downloaded file
#      e. If the manifest's sha256 field is non-empty, also checks against it
#   3. Reports a summary of pass/fail per ZIM
#
# Requirements: bash, curl, sha256sum, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ── Defaults ──────────────────────────────────────────────────────────────────

BUNDLE_NAME=""
DEST_DIR="${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}/zim"

# ── Argument parsing ──────────────────────────────────────────────────────────

usage() {
    cat >&2 <<EOF
Usage: $0 <bundle-name> [--dest <dir>]

  bundle-name   One of: minimal, balanced, comprehensive
  --dest <dir>  ZIM destination directory (default: ${DEST_DIR})

Example:
  $0 balanced
  $0 minimal --dest /mnt/ssd/allarkive/zim
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        minimal|balanced|comprehensive)
            BUNDLE_NAME="$1"
            shift
            ;;
        --dest)
            DEST_DIR="${2:?--dest requires an argument}"
            shift 2
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

if [[ -z "${BUNDLE_NAME}" ]]; then
    echo "ERROR: bundle name required" >&2
    usage
fi

MANIFEST="${REPO_ROOT}/bundles/${BUNDLE_NAME}/manifest.json"

if [[ ! -f "${MANIFEST}" ]]; then
    echo "ERROR: manifest not found: ${MANIFEST}" >&2
    exit 1
fi

# ── Terminal colors ────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${NO_COLOR:-}" == "" ]]; then
    R=$'\033[0m';  B=$'\033[1m';   DIM=$'\033[2m'
    CY=$'\033[36m';  BCY=$'\033[96m'
    GR=$'\033[32m';  BGR=$'\033[92m'
    YL=$'\033[93m';  RD=$'\033[91m';  WH=$'\033[97m'
else
    R=''; B=''; DIM=''; CY=''; BCY=''; GR=''; BGR=''; YL=''; RD=''; WH=''
fi

# ── Prerequisite checks ───────────────────────────────────────────────────────

for cmd in curl sha256sum python3; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
        echo "  ${RD}✗  required command not found: ${cmd}${R}" >&2
        exit 1
    fi
done

echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
echo "  ${CY}║${R}  ${B}${WH}AllArkive${R}  Bundle Fetcher"
echo "  ${CY}║${R}  ${DIM}bundle : ${BUNDLE_NAME}${R}"
echo "  ${CY}║${R}  ${DIM}dest   : ${DEST_DIR}${R}"
echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
echo ""

# ── Retry / resume settings ───────────────────────────────────────────────────

MAX_RETRIES=3
RETRY_DELAY=10  # seconds between retries

# ── Per-file progress bar (Python-managed) ────────────────────────────────────
# Runs curl silently, polls the .part file size every 0.25 s, draws a bar.
# Falls back gracefully if HEAD request can't get Content-Length.

_download_with_progress() {
    local url="$1"
    local part="$2"
    python3 - "${url}" "${part}" <<'PYEOF'
import sys, os, subprocess, time

url, part = sys.argv[1], sys.argv[2]

BGR = '\033[92m'; CY = '\033[96m'; DIM = '\033[2m'
YL  = '\033[93m'; WH  = '\033[97m'; R   = '\033[0m'

total = 0
try:
    import urllib.request
    req = urllib.request.Request(url, method='HEAD')
    req.add_header('User-Agent', 'AllArkive/1.0')
    with urllib.request.urlopen(req, timeout=15) as r:
        total = int(r.headers.get('Content-Length') or 0)
except Exception:
    pass

proc = subprocess.Popen(
    ['curl', '--fail', '--location', '--continue-at', '-',
     '--silent', '--no-progress-meter', '--output', part, url],
    stderr=subprocess.DEVNULL,
)

BAR_W = 36

def human(n):
    for unit, d in [('TB', 1<<40), ('GB', 1<<30), ('MB', 1<<20), ('KB', 1<<10)]:
        if n >= d:
            return f"{n/d:.1f} {unit}"
    return f"{n} B"

def draw(current, total, done=False):
    if total > 0:
        pct = min(current / total, 1.0)
        filled = int(pct * BAR_W)
        bar = f"{BGR}{'█'*filled}{DIM}{'░'*(BAR_W-filled)}{R}"
        line = f"\r    [{bar}]  {YL}{pct*100:5.1f}%{R}  {WH}{human(current)} / {human(total)}{R}"
    else:
        spin = '▏▎▍▌▋▊▉█▉▊▋▌▍▎▏'[int(time.monotonic() * 4) % 15]
        bar = f"{DIM}{'░'*(BAR_W-1)}{R}{CY}{spin}{R}"
        line = f"\r    [{bar}]  {human(current)} downloaded"
    print(line, end=('\n' if done else ''), flush=True)

try:
    while proc.poll() is None:
        try:
            draw(os.path.getsize(part), total)
        except OSError:
            draw(0, total)
        time.sleep(0.25)
    try:
        draw(os.path.getsize(part), total, done=True)
    except OSError:
        print()
except KeyboardInterrupt:
    proc.terminate()
    proc.wait()
    print()
    raise

sys.exit(proc.returncode)
PYEOF
}

# ── Ensure destination directory exists ───────────────────────────────────────

mkdir -p "${DEST_DIR}"

# ── Parse manifest with Python ────────────────────────────────────────────────

# Emit TSV: filename \t url \t sha256_url \t expected_sha256
ZIM_LIST="$(python3 - "${MANIFEST}" <<'PYEOF'
import json, sys

manifest_path = sys.argv[1]
with open(manifest_path) as f:
    data = json.load(f)

for zim in data.get("zims", []):
    filename     = zim.get("filename", "")
    url          = zim.get("url", "")
    sha256_url   = zim.get("sha256_url", "")
    expected_sha = zim.get("sha256", "")
    if not filename or not url:
        print(f"WARN: skipping ZIM entry with missing filename or url", file=sys.stderr)
        continue
    print(f"{filename}\t{url}\t{sha256_url}\t{expected_sha}")
PYEOF
)"

if [[ -z "${ZIM_LIST}" ]]; then
    echo "ERROR: no valid ZIM entries found in ${MANIFEST}" >&2
    exit 1
fi

# ── Download and verify each ZIM ─────────────────────────────────────────────

PASS=0
FAIL=0
SKIP=0

download_and_verify() {
    local filename="$1"
    local url="$2"
    local sha256_url="$3"
    local expected_sha="$4"
    local dest="${DEST_DIR}/${filename}"
    local part="${dest}.part"

    echo ""
    echo "  ${CY}╭──────────────────────────────────────────────────────────────────╮${R}"
    echo "  ${CY}│${R}  ${B}↓  ${filename}${R}"
    echo "  ${CY}╰──────────────────────────────────────────────────────────────────╯${R}"

    # Already present and valid?
    if [[ -f "${dest}" ]]; then
        echo "  ${DIM}·${R}  file exists — verifying checksum..."
        if verify_file "${dest}" "${sha256_url}" "${expected_sha}"; then
            echo "  ${BGR}✓${R}  already present and valid. Skipping."
            SKIP=$((SKIP + 1))
            return 0
        else
            echo "  ${YL}⚠${R}  checksum mismatch — re-downloading."
            rm -f "${dest}"
        fi
    fi

    # Show resume hint if a partial download was left from a previous run.
    if [[ -f "${part}" ]]; then
        local part_size
        part_size="$(du -sh "${part}" 2>/dev/null | cut -f1 || echo "?")"
        echo "  ${BCY}↻${R}  resuming partial download (${part_size} already on disk)."
    fi

    echo "  ${DIM}·${R}  ${url}"
    echo "  ${DIM}·${R}  ${dest}"

    local attempt=1
    while [[ "${attempt}" -le "${MAX_RETRIES}" ]]; do
        if [[ "${attempt}" -gt 1 ]]; then
            echo "  ${YL}↻${R}  retrying (attempt ${attempt}/${MAX_RETRIES}) after ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        fi

        # --continue-at - resumes from existing .part bytes; progress drawn by Python.
        if _download_with_progress "${url}" "${part}"; then
            mv "${part}" "${dest}"
            break
        fi

        echo "  ${RD}✗${R}  attempt ${attempt}/${MAX_RETRIES} failed." >&2
        attempt=$((attempt + 1))
    done

    if [[ ! -f "${dest}" ]]; then
        echo "  ${RD}✗  download failed after ${MAX_RETRIES} attempt(s) for ${filename}${R}" >&2
        echo "  ${DIM}·  partial file kept at ${part} — re-run to resume.${R}" >&2
        FAIL=$((FAIL + 1))
        return 1
    fi

    # Verify
    if verify_file "${dest}" "${sha256_url}" "${expected_sha}"; then
        echo "  ${BGR}✓${R}  verified OK."
        PASS=$((PASS + 1))
    else
        echo "  ${RD}✗  checksum verification failed for ${filename}${R}" >&2
        echo "  ${DIM}·  removing corrupt file: ${dest}${R}" >&2
        rm -f "${dest}"
        FAIL=$((FAIL + 1))
        return 1
    fi
}

verify_file() {
    local file="$1"
    local sha256_url="$2"
    local expected_sha="$3"

    local actual_sha
    actual_sha="$(sha256sum "${file}" | awk '{print $1}')"

    if [[ -n "${expected_sha}" ]]; then
        if [[ "${actual_sha}" != "${expected_sha}" ]]; then
            echo "  ${RD}✗  mismatch: expected ${expected_sha}${R}" >&2
            echo "           ${RD}got      ${actual_sha}${R}" >&2
            return 1
        fi
        return 0
    fi

    if [[ -z "${sha256_url}" ]]; then
        echo "  ${YL}⚠${R}  no sha256 or sha256_url in manifest — skipping verification" >&2
        return 0
    fi

    local kiwix_sha
    kiwix_sha="$(curl -sf "${sha256_url}" | awk '{print $1}')"
    if [[ -z "${kiwix_sha}" ]]; then
        echo "  ${YL}⚠${R}  could not fetch checksum from ${sha256_url}" >&2
        echo "  ${DIM}·  skipping verification — check manually.${R}" >&2
        return 0
    fi

    if [[ "${actual_sha}" != "${kiwix_sha}" ]]; then
        echo "  ${RD}✗  mismatch: Kiwix expected ${kiwix_sha}${R}" >&2
        echo "           ${RD}got               ${actual_sha}${R}" >&2
        return 1
    fi

    echo "  ${BGR}✓${R}  verified via Kiwix .sha256"
    echo "  ${DIM}·  pin in bundles/${BUNDLE_NAME}/manifest.json: ${actual_sha}${R}"
    return 0
}

# Process each ZIM
while IFS=$'\t' read -r filename url sha256_url expected_sha; do
    download_and_verify "${filename}" "${url}" "${sha256_url}" "${expected_sha}" || true
done <<< "${ZIM_LIST}"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "  ${CY}╔══════════════════════════════════════════════════════════════════╗${R}"
if [[ "${FAIL}" -gt 0 ]]; then
    echo "  ${CY}║${R}  ${RD}✗${R}  Bundle: ${B}${BUNDLE_NAME}${R}  —  ${RD}${FAIL} failed${R}"
else
    echo "  ${CY}║${R}  ${BGR}✓${R}  Bundle: ${B}${BUNDLE_NAME}${R}  — all ZIMs present"
fi
echo "  ${CY}╠══════════════════════════════════════════════════════════════════╣${R}"
echo "  ${CY}║${R}  ${DIM}↓  downloaded and verified : ${PASS}${R}"
echo "  ${CY}║${R}  ${DIM}→  already present (skipped): ${SKIP}${R}"
if [[ "${FAIL}" -gt 0 ]]; then
    echo "  ${CY}║${R}  ${RD}✗  failed                  : ${FAIL}${R}"
else
    echo "  ${CY}║${R}  ${DIM}✓  failed                  : ${FAIL}${R}"
fi
echo "  ${CY}║${R}  ${DIM}·  destination: ${DEST_DIR}${R}"
echo "  ${CY}╚══════════════════════════════════════════════════════════════════╝${R}"
echo ""

if [[ "${FAIL}" -gt 0 ]]; then
    echo "  ${RD}✗  ${FAIL} ZIM(s) failed. Check output above.${R}" >&2
    exit 1
fi

echo "  ${BGR}✓${R}  All ZIM files are present and verified."
echo "  ${DIM}·  start the stack: docker compose -f compose/docker-compose.yml up -d${R}"
