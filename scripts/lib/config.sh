# shellcheck shell=bash
# scripts/lib/config.sh — read/write ~/.config/allarkive/config.json.
#
# Reads ALLARKIVE_CONFIG and ALLARKIVE_CONFIG_DIR (set in bootstrap.sh).

_cfg_get() {
    # Prints the value for <key> from config.json, or empty string if absent.
    local key="$1"
    if [[ ! -f "${ALLARKIVE_CONFIG}" ]]; then
        echo ""; return 0
    fi
    python3 - "${ALLARKIVE_CONFIG}" "${key}" <<'PYEOF'
import json, sys, os
try:
    with open(sys.argv[1]) as f:
        val = json.load(f).get(sys.argv[2]) or ""
    print(os.path.expanduser(str(val)) if val else "")
except Exception:
    print("")
PYEOF
}

_cfg_save() {
    # Merge key=value pairs into config.json. Args: key val [key val ...]
    mkdir -p "${ALLARKIVE_CONFIG_DIR}"
    python3 - "${ALLARKIVE_CONFIG}" "$@" <<'PYEOF'
import json, sys
path, pairs = sys.argv[1], sys.argv[2:]
try:
    cfg = json.loads(open(path).read())
except Exception:
    cfg = {}
for i in range(0, len(pairs) - 1, 2):
    cfg[pairs[i]] = pairs[i + 1]
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
}
