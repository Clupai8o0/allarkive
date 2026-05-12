# shellcheck shell=bash
# scripts/lib/env-file.sh — compose/.env mutation + port resolution.
#
# Reads ENV_FILE and KEEP_ENV (set in bootstrap.sh) at call time.

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
    # --keep-env: honour whatever is in .env, only bump on conflict.
    # default:    always start from DEFAULT so ports reset to well-known values
    #             on every run and only increment if those values are occupied.
    local varname="$1" default="$2"
    local preferred
    if [[ "${KEEP_ENV}" == true ]]; then
        preferred="$(grep -E "^${varname}=" "${ENV_FILE}" 2>/dev/null | cut -d= -f2- || true)"
        preferred="${preferred:-${default}}"
    else
        preferred="${default}"
    fi
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
