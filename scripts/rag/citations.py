"""Rewrite [N] citation markers in model output to kiwix article links."""

import re


def rewrite_citations(text: str, passages: list[dict], kiwix_public_url: str) -> str:
    base = kiwix_public_url.rstrip("/")

    def _replace(m: re.Match) -> str:
        n = int(m.group(1))
        if n < 1 or n > len(passages):
            return m.group(0)
        p = passages[n - 1]
        url = f"{base}/{p['zim_name']}/{p['article_path']}"
        label = p.get("title") or p["article_path"].rsplit("/", 1)[-1].replace("_", " ")
        return f"[[{n}: {label}]]({url})"

    return re.sub(r"\[(\d+)\]", _replace, text)
