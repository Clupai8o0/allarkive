#!/usr/bin/env python3
"""Build or extend bundles/custom/manifest.json from URLs and/or Kiwix handles.

Called by ``scripts/fetch-bundle.sh custom --add <spec> [--add ...]``. Each
spec is one of:

  * Full URL (``http://`` or ``https://``) — used as-is.
  * Kiwix handle (e.g. ``wikipedia_en_simple_all_maxi_2026-03``) — resolved
    to ``https://download.kiwix.org/zim/<category>/<handle>.zim`` by
    mapping the leading segment to a Kiwix project directory.

Resolution is best-effort. For project families not in the prefix table
(rare science wikis, project subdomains, etc.), pass the full URL.

Idempotent: re-running with the same specs is a no-op. New specs are
appended to the existing manifest.
"""

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Map the first underscore-separated segment of a handle to the
# corresponding subdirectory under https://download.kiwix.org/zim/.
KIWIX_CATEGORIES: dict[str, str] = {
    "wikipedia": "wikipedia",
    "wiktionary": "wiktionary",
    "wikiquote": "wikiquote",
    "wikisource": "wikisource",
    "wikibooks": "wikibooks",
    "wikiversity": "wikiversity",
    "wikivoyage": "wikivoyage",
    "wikinews": "wikinews",
    "ifixit": "ifixit",
    "gutenberg": "gutenberg",
    "ted": "ted",
    "phet": "phet",
    "rachel": "rachel",
    "vikidia": "vikidia",
    "khanacademy": "other",
    "fonoteca": "other",
}

# Stack Exchange family lives under /zim/stack_exchange/.
SE_SUFFIX = re.compile(
    r"^(stackoverflow\.com|superuser\.com|askubuntu\.com|serverfault\.com|"
    r".+\.stackexchange\.com)"
)


def resolve_handle(handle: str) -> str | None:
    """Return a download URL for a Kiwix handle, or None if unresolved."""
    h = handle.strip()
    if h.endswith(".zim"):
        h = h[: -len(".zim")]

    if SE_SUFFIX.match(h):
        return f"https://download.kiwix.org/zim/stack_exchange/{h}.zim"

    head = h.split("_", 1)[0]
    cat = KIWIX_CATEGORIES.get(head.lower())
    if cat:
        return f"https://download.kiwix.org/zim/{cat}/{h}.zim"

    return None


def head_size(url: str) -> int:
    """HEAD-request a URL and return Content-Length in bytes, or 0 on failure."""
    try:
        req = urllib.request.Request(url, method="HEAD")
        req.add_header("User-Agent", "AllArkive/1.0")
        with urllib.request.urlopen(req, timeout=15) as r:
            return int(r.headers.get("Content-Length") or 0)
    except Exception:
        return 0


def build_entry(spec: str) -> dict:
    """Build a manifest entry from a URL or a Kiwix handle."""
    spec = spec.strip()
    if spec.startswith(("http://", "https://")):
        url = spec
    else:
        resolved = resolve_handle(spec)
        if not resolved:
            raise SystemExit(
                f"\n  ERROR: cannot resolve Kiwix handle '{spec}'.\n"
                f"         Browse https://library.kiwix.org/ to find the ZIM,\n"
                f"         then pass the full URL with --add <url>.\n"
            )
        url = resolved

    filename = url.rsplit("/", 1)[-1]
    if not filename.endswith(".zim"):
        raise SystemExit(f"\n  ERROR: URL does not end in .zim: {url}\n")

    size_bytes = head_size(url)
    return {
        "name": filename[:-4].replace("_", " "),
        "filename": filename,
        "url": url,
        "sha256": "",
        "sha256_url": f"{url}.sha256",
        "approx_size_gb": round(size_bytes / 1e9, 2) if size_bytes else 0,
        "license": "User-supplied — check upstream",
        "license_url": "",
        "license_notes": "Custom bundle. Verify the source license before "
                          "redistributing the resulting ZIM.",
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "specs",
        nargs="+",
        help="URLs or Kiwix handles to add to bundles/custom/manifest.json",
    )
    args = ap.parse_args()

    manifest_path = REPO_ROOT / "bundles" / "custom" / "manifest.json"
    manifest_path.parent.mkdir(parents=True, exist_ok=True)

    if manifest_path.exists():
        with open(manifest_path) as f:
            manifest = json.load(f)
    else:
        manifest = {
            "_comment": (
                "Custom bundle. Built incrementally by "
                "scripts/build-custom-manifest.py. Per-archive license info "
                "is user-supplied — verify before redistributing."
            ),
            "name": "custom",
            "description": "User-defined bundle.",
            "version": "1.0",
            "hardware": {
                "min_free_disk_gb": 1,
                "recommended_free_disk_gb": 5,
                "min_ram_gb": 4,
                "notes": (
                    "Sizes computed from upstream Content-Length headers at "
                    "manifest build time. Adjust if HEAD requests failed."
                ),
            },
            "model": {
                "name": "qwen2.5:7b",
                "notes": "Pass --model to bootstrap.sh to override.",
            },
            "zims": [],
        }

    existing = {z.get("url"): z for z in manifest.get("zims", [])}
    added: list[dict] = []
    for spec in args.specs:
        entry = build_entry(spec)
        if entry["url"] in existing:
            print(f"  · already in manifest: {entry['filename']}")
            continue
        manifest["zims"].append(entry)
        existing[entry["url"]] = entry
        added.append(entry)

    total_gb = sum(z.get("approx_size_gb", 0) for z in manifest["zims"])
    manifest["hardware"]["min_free_disk_gb"] = max(1, int(total_gb * 1.1) + 1)
    manifest["hardware"]["recommended_free_disk_gb"] = max(5, int(total_gb * 1.3) + 1)
    manifest["description"] = (
        f"User-defined bundle: {len(manifest['zims'])} archive(s), "
        f"~{total_gb:.1f} GB ZIM total."
    )

    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")

    print(f"  ✓ wrote {manifest_path}")
    print(f"    {len(manifest['zims'])} ZIM(s), ~{total_gb:.1f} GB total")
    for e in added:
        sz = e.get("approx_size_gb", 0)
        sz_str = f"{sz:.1f} GB" if sz else "size unknown"
        print(f"    + {e['filename']}  ({sz_str})")
    if not added:
        print("    (no new entries — all specs were already present)")


if __name__ == "__main__":
    main()
