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

# ── Prerequisite checks ───────────────────────────────────────────────────────

for cmd in curl sha256sum python3; do
    if ! command -v "${cmd}" > /dev/null 2>&1; then
        echo "ERROR: required command not found: ${cmd}" >&2
        exit 1
    fi
done

# ── Retry / resume settings ───────────────────────────────────────────────────

MAX_RETRIES=3
RETRY_DELAY=10  # seconds between retries

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

    echo "──────────────────────────────────────────────────────────────────────────"
    echo "ZIM: ${filename}"

    # Already present and valid?
    if [[ -f "${dest}" ]]; then
        echo "  File exists — verifying checksum..."
        if verify_file "${dest}" "${sha256_url}" "${expected_sha}"; then
            echo "  Already present and valid. Skipping download."
            SKIP=$((SKIP + 1))
            return 0
        else
            echo "  Checksum mismatch — re-downloading."
            rm -f "${dest}"
        fi
    fi

    # Show resume hint if a partial download was left from a previous run.
    if [[ -f "${part}" ]]; then
        local part_size
        part_size="$(du -sh "${part}" 2>/dev/null | cut -f1 || echo "?")"
        echo "  Resuming partial download (${part_size} already on disk)."
    fi

    echo "  Downloading from: ${url}"
    echo "  Destination: ${dest}"
    echo "  (Large files — this may take a while on a slow connection.)"

    local attempt=1
    while [[ "${attempt}" -le "${MAX_RETRIES}" ]]; do
        if [[ "${attempt}" -gt 1 ]]; then
            echo "  Retrying (attempt ${attempt}/${MAX_RETRIES}) after ${RETRY_DELAY}s..."
            sleep "${RETRY_DELAY}"
        fi

        # --continue-at - resumes into the .part file if it already has bytes.
        if curl --fail --location --continue-at - --progress-bar \
                 --output "${part}" "${url}"; then
            mv "${part}" "${dest}"
            break
        fi

        echo "  Attempt ${attempt}/${MAX_RETRIES} failed." >&2
        attempt=$((attempt + 1))
    done

    if [[ ! -f "${dest}" ]]; then
        echo "  ERROR: download failed after ${MAX_RETRIES} attempt(s) for ${filename}" >&2
        echo "  Partial file kept at ${part} — re-run to resume." >&2
        FAIL=$((FAIL + 1))
        return 1
    fi

    # Verify
    if verify_file "${dest}" "${sha256_url}" "${expected_sha}"; then
        echo "  Verified OK."
        PASS=$((PASS + 1))
    else
        echo "  ERROR: checksum verification failed for ${filename}" >&2
        echo "  Removing corrupt file: ${dest}" >&2
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

    # If the manifest has a pinned SHA-256, check against it first.
    if [[ -n "${expected_sha}" ]]; then
        if [[ "${actual_sha}" != "${expected_sha}" ]]; then
            echo "  MISMATCH: manifest expected ${expected_sha}" >&2
            echo "            got               ${actual_sha}" >&2
            return 1
        fi
        return 0
    fi

    # No pinned SHA-256 in manifest — download from official Kiwix source.
    if [[ -z "${sha256_url}" ]]; then
        echo "  WARN: no sha256 or sha256_url in manifest — skipping verification" >&2
        return 0
    fi

    local kiwix_sha
    kiwix_sha="$(curl -sf "${sha256_url}" | awk '{print $1}')"
    if [[ -z "${kiwix_sha}" ]]; then
        echo "  WARN: could not fetch checksum from ${sha256_url}" >&2
        echo "  Skipping verification — manually check the file." >&2
        return 0
    fi

    if [[ "${actual_sha}" != "${kiwix_sha}" ]]; then
        echo "  MISMATCH: Kiwix expected ${kiwix_sha}" >&2
        echo "            got            ${actual_sha}" >&2
        return 1
    fi

    # Pin the verified hash back to the manifest as a note (not written to disk).
    echo "  Verified via Kiwix .sha256 file."
    echo "  Pin this hash in bundles/${BUNDLE_NAME}/manifest.json: ${actual_sha}"
    return 0
}

# Process each ZIM
while IFS=$'\t' read -r filename url sha256_url expected_sha; do
    download_and_verify "${filename}" "${url}" "${sha256_url}" "${expected_sha}" || true
done <<< "${ZIM_LIST}"

# ── Summary ───────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════════════════════════════════"
echo "Bundle: ${BUNDLE_NAME}"
echo "Destination: ${DEST_DIR}"
echo "Downloaded and verified: ${PASS}"
echo "Already present (skipped): ${SKIP}"
echo "Failed: ${FAIL}"
echo "══════════════════════════════════════════════════════════════════════════"

if [[ "${FAIL}" -gt 0 ]]; then
    echo "ERROR: ${FAIL} ZIM(s) failed. Check output above." >&2
    exit 1
fi

echo ""
echo "All ZIM files are present and verified."
echo "Start the stack with: docker compose -f compose/docker-compose.yml up -d"
