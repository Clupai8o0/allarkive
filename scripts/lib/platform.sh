# shellcheck shell=bash
# scripts/lib/platform.sh — platform / RAM / GPU detection.
#
# Detection: Darwin → mac; Linux + Raspberry Pi marker → pi; Linux + WSL marker
# → wsl; anything else Linux → linux. Used to pick compose file, data dir, and
# bundle/model defaults. Override with --platform or the per-flag overrides.

_detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "mac"; return ;;
        Linux)
            if [[ -r /proc/device-tree/model ]] \
               && grep -qi "raspberry pi" /proc/device-tree/model 2>/dev/null; then
                echo "pi"; return
            fi
            if [[ -r /proc/version ]] \
               && grep -qiE "microsoft|wsl" /proc/version 2>/dev/null; then
                echo "wsl"; return
            fi
            echo "linux"
            ;;
        *) echo "linux" ;;
    esac
}

_detect_ram_gb() {
    case "$(uname -s)" in
        Darwin)
            python3 -c "import subprocess; print(int(subprocess.check_output(['sysctl','-n','hw.memsize']))//(1024**3))" 2>/dev/null || echo 0
            ;;
        Linux)
            awk '/^MemTotal:/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 0
            ;;
        *) echo 0 ;;
    esac
}

_detect_gpu() {
    if command -v nvidia-smi > /dev/null 2>&1 && nvidia-smi -L > /dev/null 2>&1; then
        nvidia-smi -L | head -1 | sed 's/ (UUID.*//'
        return
    fi
    if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "arm64" ]]; then
        echo "Apple Silicon — Metal available to host-native Ollama only"
        return
    fi
    echo "none"
}

# Docker Desktop's memory ceiling (mac/wsl). Linux Docker uses host memory directly.
_detect_docker_ram_gb() {
    if ! docker info > /dev/null 2>&1; then echo 0; return; fi
    # docker info reports "Total Memory: 7.652GiB" — parse the leading number.
    docker info 2>/dev/null \
        | awk -F': *' '/^[[:space:]]*Total Memory:/ {gsub(/GiB|GB|MiB|MB/,"",$2); print int($2); exit}' \
        || echo 0
}
