#!/usr/bin/env bash
# teardown.sh — stop the AllArkive Docker Compose stack
#
# Usage:
#   scripts/teardown.sh              # stop default stack
#   scripts/teardown.sh --pi         # stop Pi stack (docker-compose.pi.yml)
#   scripts/teardown.sh --volumes    # also remove named volumes (wipes data!)
#   scripts/teardown.sh --pi-archive # stop Pi archive-only stack
#
# Mirrors the compose-file selection logic of bootstrap.sh.
# Does NOT touch a locally-running Ollama process — only the Docker stack.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
COMPOSE_DIR="${REPO_ROOT}/compose"

COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.yml"
EXTRA_ARGS=()

usage() {
    cat >&2 <<EOF
Usage: $0 [options]

  --pi           Stop the Raspberry Pi stack (docker-compose.pi.yml)
  --pi-archive   Stop the Pi archive-only stack (docker-compose.pi-archive.yml)
  --volumes      Also remove named volumes — WARNING: wipes persisted data
  -h, --help     Show this message
EOF
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --pi)         COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi.yml"; shift ;;
        --pi-archive) COMPOSE_FILE="${COMPOSE_DIR}/docker-compose.pi-archive.yml"; shift ;;
        --volumes)    EXTRA_ARGS+=(--volumes); shift ;;
        -h|--help)    usage ;;
        *) echo "ERROR: unknown argument: $1" >&2; usage ;;
    esac
done

ENV_FILE="${COMPOSE_DIR}/.env"

if [[ ! -f "${COMPOSE_FILE}" ]]; then
    echo "ERROR: compose file not found: ${COMPOSE_FILE}" >&2
    exit 1
fi

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "ERROR: ${ENV_FILE} not found — stack may never have been started." >&2
    exit 1
fi

echo "  Stopping AllArkive stack: ${COMPOSE_FILE}"
docker compose -f "${COMPOSE_FILE}" --env-file "${ENV_FILE}" down "${EXTRA_ARGS[@]}"
echo "  Stack stopped."

if [[ " ${EXTRA_ARGS[*]:-} " == *" --volumes "* ]]; then
    echo "  Named volumes removed."
fi
