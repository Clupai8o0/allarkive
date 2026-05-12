#!/usr/bin/env python3
"""Build static HTML docs from the repository's markdown files.

Run from the repo root:

    python3 scripts/build-docs.py

Outputs HTML files alongside the docs/ tree (GitHub Pages root). Each page has
the same sidebar (grouped doc index) and a sticky right-hand TOC derived from
the headings of that page. Internal .md links are rewritten to point to the
generated .html pages.

Requires `pandoc` on PATH (already a project dep).
"""

from __future__ import annotations

import html
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DOCS_ROOT = REPO_ROOT / "docs"


@dataclass(frozen=True)
class DocEntry:
    title: str
    source: Path           # relative to REPO_ROOT
    output: Path           # relative to DOCS_ROOT


@dataclass(frozen=True)
class DocSection:
    name: str
    entries: tuple[DocEntry, ...]


SECTIONS: tuple[DocSection, ...] = (
    DocSection(
        "Overview",
        (
            DocEntry("README",        Path("README.MD"),               Path("readme.html")),
            DocEntry("Architecture",  Path("docs/ARCHITECTURE.MD"),    Path("architecture.html")),
            DocEntry("Roadmap",       Path("ROADMAP.MD"),              Path("roadmap.html")),
            DocEntry("Threat model",  Path("docs/THREAT_MODEL.md"),    Path("threat-model.html")),
            DocEntry("Design",        Path("docs/DESIGN.MD"),          Path("design.html")),
            DocEntry("Brief",         Path("docs/BRIEF.md"),           Path("brief.html")),
            DocEntry("Docs index",    Path("DOCS.MD"),                 Path("docs-index.html")),
            DocEntry("Changelog",     Path("CHANGELOG.MD"),            Path("changelog.html")),
        ),
    ),
    DocSection(
        "Install",
        (
            DocEntry("Laptop / desktop (Linux)", Path("docs/install/laptop.md"),  Path("install/laptop.html")),
            DocEntry("macOS",                    Path("docs/install/macos.md"),   Path("install/macos.html")),
            DocEntry("Windows (WSL2)",           Path("docs/install/windows.md"), Path("install/windows.html")),
            DocEntry("Headless server",          Path("docs/install/server.md"),  Path("install/server.html")),
        ),
    ),
    DocSection(
        "Deployment",
        (
            DocEntry("Raspberry Pi (full stack)", Path("docs/deployment/pi-text-only.md"),     Path("deployment/pi-text-only.html")),
            DocEntry("Pi as archive node",        Path("docs/deployment/pi-archive-only.md"), Path("deployment/pi-archive-only.html")),
            DocEntry("Split across two machines", Path("docs/deployment/split.md"),           Path("deployment/split.html")),
            DocEntry("Opt-in LAN access",         Path("docs/deployment/lan-access.md"),      Path("deployment/lan-access.html")),
        ),
    ),
    DocSection(
        "Bundles",
        (
            DocEntry("Bundles overview", Path("docs/bundles/README.md"), Path("bundles/index.html")),
        ),
    ),
    DocSection(
        "Community",
        (
            DocEntry("Contributing",     Path("CONTRIBUTING.MD"),     Path("contributing.html")),
            DocEntry("Code of conduct",  Path("CODE_OF_CONDUCT.MD"),  Path("code-of-conduct.html")),
            DocEntry("Governance",       Path("GOVERNANCE.MD"),       Path("governance.html")),
            DocEntry("Security",         Path("SECURITY.MD"),         Path("security.html")),
        ),
    ),
)


def all_entries() -> list[DocEntry]:
    return [e for s in SECTIONS for e in s.entries]


def source_to_output() -> dict[str, Path]:
    """Map normalized source path (str, lowercase) -> output path (relative to docs/)."""
    out: dict[str, Path] = {}
    for entry in all_entries():
        out[str(entry.source).lower()] = entry.output
    return out


SRC_TO_OUT = source_to_output()


HEADING_RE = re.compile(r'<h([1-6])\s+id="([^"]+)"[^>]*>(.*?)</h\1>', re.DOTALL)
TAG_STRIP_RE = re.compile(r"<[^>]+>")


def extract_toc(body_html: str) -> list[tuple[int, str, str]]:
    """Return [(level, id, text)] for h2 + h3 headings in the body."""
    toc: list[tuple[int, str, str]] = []
    for match in HEADING_RE.finditer(body_html):
        level = int(match.group(1))
        if level not in (2, 3):
            continue
        anchor = match.group(2)
        text = TAG_STRIP_RE.sub("", match.group(3)).strip()
        toc.append((level, anchor, html.unescape(text)))
    return toc


def render_toc(toc: list[tuple[int, str, str]]) -> str:
    if not toc:
        return ""
    lines = ['<nav class="doc-toc" aria-label="On this page">',
             '<p class="doc-toc-label">On this page</p>',
             '<ul>']
    for level, anchor, text in toc:
        cls = "toc-h2" if level == 2 else "toc-h3"
        lines.append(f'<li class="{cls}"><a href="#{anchor}">{html.escape(text)}</a></li>')
    lines.append("</ul></nav>")
    return "\n".join(lines)


def render_sidebar(active_output: Path) -> str:
    """Generate the sidebar HTML. Links are computed relative to the active page."""
    active_dir = active_output.parent
    parts = ['<aside class="doc-sidebar" aria-label="Documentation">',
             '<a class="sidebar-home" href="' + rel_link(active_dir, Path("index.html")) + '">',
             '<span class="sidebar-home-name">AllArkive</span>',
             '<span class="sidebar-home-tag">docs</span>',
             '</a>']
    for section in SECTIONS:
        parts.append(f'<p class="sidebar-section">{html.escape(section.name)}</p>')
        parts.append('<ul>')
        for entry in section.entries:
            href = rel_link(active_dir, entry.output)
            active = " aria-current=\"page\"" if entry.output == active_output else ""
            parts.append(f'<li><a href="{href}"{active}>{html.escape(entry.title)}</a></li>')
        parts.append('</ul>')
    parts.append('</aside>')
    return "\n".join(parts)


def rel_link(from_dir: Path, to_file: Path) -> str:
    """Compute a relative path string from from_dir to to_file (both relative to docs/)."""
    from_parts = from_dir.parts
    to_parts = to_file.parts
    # Find common prefix
    i = 0
    while i < len(from_parts) and i < len(to_parts) - 1 and from_parts[i] == to_parts[i]:
        i += 1
    up = [".."] * (len(from_parts) - i)
    down = list(to_parts[i:])
    pieces = up + down
    return "/".join(pieces) if pieces else "."


def rewrite_links(body_html: str, source: Path, active_output: Path) -> str:
    """Rewrite href="...md" to the corresponding generated .html path.

    `source` is the markdown file's path relative to REPO_ROOT, used to resolve
    relative links. `active_output` is the page's output path relative to docs/.
    """
    active_dir = active_output.parent
    source_dir = source.parent  # relative to REPO_ROOT

    def replace(match: re.Match[str]) -> str:
        prefix, href, suffix = match.group(1), match.group(2), match.group(3)
        if href.startswith(("http://", "https://", "mailto:", "#")):
            return match.group(0)
        fragment = ""
        target = href
        if "#" in target:
            target, fragment = target.split("#", 1)
            fragment = "#" + fragment
        if not target.lower().endswith(".md"):
            return match.group(0)
        # Resolve target relative to the source file's directory, then normalize.
        # Absolute-looking paths (start with /) are treated as repo-relative.
        if target.startswith("/"):
            resolved = Path(target.lstrip("/"))
        else:
            resolved = (source_dir / target)
        # Collapse .. and . segments without touching the filesystem
        try:
            resolved = Path(*Path(resolved).parts)
            normalized_parts: list[str] = []
            for part in resolved.parts:
                if part == "..":
                    if normalized_parts:
                        normalized_parts.pop()
                elif part != ".":
                    normalized_parts.append(part)
            resolved = Path(*normalized_parts) if normalized_parts else Path(".")
        except ValueError:
            return match.group(0)
        candidate = str(resolved).lower()
        out = SRC_TO_OUT.get(candidate)
        if out is None:
            return match.group(0)
        new_href = rel_link(active_dir, out) + fragment
        return f'{prefix}{new_href}{suffix}'

    pattern = re.compile(r'(href=")([^"]+)(")')
    return pattern.sub(replace, body_html)


def pandoc_to_html(md_path: Path) -> str:
    result = subprocess.run(
        ["pandoc", "--from=gfm", "--to=html5", "--no-highlight", str(md_path)],
        capture_output=True,
        text=True,
        check=True,
    )
    return result.stdout


PAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{title} — AllArkive docs</title>
    <meta name="description" content="AllArkive documentation: {title}.">
    <link rel="stylesheet" href="{css_href}">
</head>
<body class="doc-page">
    <button class="sidebar-toggle" type="button" aria-controls="doc-sidebar" aria-expanded="false">Menu</button>
    <div class="doc-layout">
{sidebar}

        <main class="doc-main">
            <p class="doc-breadcrumb"><a href="{home_href}">AllArkive</a> / <span>{section}</span> / <span>{title}</span></p>
            <article class="doc-content">
{content}
            </article>
            <footer class="doc-footer">
                <p>Source: <code>{source}</code>. Edit on <a href="https://github.com/clupai8o0/allarkive/blob/main/{source}">GitHub</a>.</p>
                <p class="footer-meta">AllArkive · AGPL-3.0 · offline-first, locally-hosted.</p>
            </footer>
        </main>

{toc}
    </div>
    <script>
        (function () {{
            var btn = document.querySelector('.sidebar-toggle');
            var sidebar = document.querySelector('.doc-sidebar');
            if (!btn || !sidebar) return;
            sidebar.id = 'doc-sidebar';
            btn.addEventListener('click', function () {{
                var open = sidebar.classList.toggle('is-open');
                btn.setAttribute('aria-expanded', open ? 'true' : 'false');
            }});
        }})();
    </script>
</body>
</html>
"""


def section_for(entry: DocEntry) -> str:
    for section in SECTIONS:
        if entry in section.entries:
            return section.name
    return ""


def build_one(entry: DocEntry) -> None:
    src = REPO_ROOT / entry.source
    if not src.exists():
        print(f"  ! missing source: {entry.source}", file=sys.stderr)
        return
    body = pandoc_to_html(src)
    body = rewrite_links(body, entry.source, entry.output)
    toc = render_toc(extract_toc(body))
    sidebar = render_sidebar(entry.output)

    output_path = DOCS_ROOT / entry.output
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # Compute relative links for css and home from this page's directory
    depth = len(entry.output.parent.parts)
    css_href = ("../" * depth) + "styles.css" if depth else "styles.css"
    home_href = ("../" * depth) + "index.html" if depth else "index.html"

    html_doc = PAGE_TEMPLATE.format(
        title=html.escape(entry.title),
        section=html.escape(section_for(entry)),
        css_href=css_href,
        home_href=home_href,
        sidebar=sidebar,
        content=body,
        toc=toc,
        source=html.escape(str(entry.source)),
    )
    output_path.write_text(html_doc, encoding="utf-8")
    print(f"  ✓ {entry.source} → docs/{entry.output}")


def main() -> int:
    print(f"Building docs into {DOCS_ROOT}")
    for entry in all_entries():
        build_one(entry)
    print("Done.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
