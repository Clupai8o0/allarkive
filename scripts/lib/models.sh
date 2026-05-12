# shellcheck shell=bash
# scripts/lib/models.sh — Ollama model pulls with progress bars.
#
# Reads OLLAMA_URL / USE_LOCAL_OLLAMA / COMPOSE_FILE from bootstrap.sh.
# Call _pull_model_init once before _pull_model, and _pull_model_cleanup after.

_PULL_PY=""

_pull_model_init() {
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
}

_pull_model_cleanup() {
    [[ -n "${_PULL_PY}" ]] && rm -f "${_PULL_PY}"
    _PULL_PY=""
}

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
