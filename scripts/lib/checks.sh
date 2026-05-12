# shellcheck shell=bash
# scripts/lib/checks.sh — prerequisite, directory, disk, and health checks.
#
# Depends on info/warn/die from lib/ui.sh and ALLARKIVE_CONFIG from bootstrap.sh.

check_cmd() {
    command -v "$1" > /dev/null 2>&1 || die "Required command not found: $1"
}

check_dir_accessible() {
    # Returns 0 if dir exists/is creatable and writable; 1 with warnings otherwise.
    local dir="$1" label="$2"
    if mkdir -p "${dir}" 2>/dev/null && [[ -w "${dir}" ]]; then
        return 0
    fi
    warn "${label} directory is not accessible: ${dir}"
    case "${dir}" in
        /Volumes/*|/mnt/*|/media/*)
            warn "This looks like an external disk path — is the disk mounted?" ;;
    esac
    warn "Config: ${ALLARKIVE_CONFIG}"
    return 1
}

check_disk_space() {
    local required_gb="$1"
    local path="$2"
    local available_gb
    available_gb="$(df -P "${path}" | awk 'NR==2 {print int($4 / 1048576)}')"

    if [[ "${available_gb}" -lt "${required_gb}" ]]; then
        warn "Low disk space on ${path}: ${available_gb} GB available, ${required_gb} GB recommended for the ${BUNDLE} bundle."
        warn "Proceeding anyway — you can always fetch a smaller bundle with --bundle minimal."
    else
        info "Disk space OK: ${available_gb} GB available on $(df -P "${path}" | awk 'NR==2 {print $1}')."
    fi
}

wait_healthy() {
    local service="$1"
    local max_wait="${2:-120}"
    local elapsed=0
    local interval=5

    while [[ "${elapsed}" -lt "${max_wait}" ]]; do
        local status
        status="$(docker compose -f "${COMPOSE_FILE}" ps --format json "${service}" 2>/dev/null \
                  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('Health','unknown'))" \
                  2>/dev/null || echo "unknown")"

        if [[ "${status}" == "healthy" ]]; then
            echo "  ${BGR}✓${R}  ${service}: healthy"
            return 0
        fi

        sleep "${interval}"
        elapsed=$((elapsed + interval))
        printf "  ${DIM}·${R}  waiting for %s  %ds / %ds...\r" "${service}" "${elapsed}" "${max_wait}"
    done

    warn "${service} did not become healthy within ${max_wait}s."
    warn "Check logs: docker compose -f ${COMPOSE_FILE} logs ${service}"
    return 1
}
