# Adding your own documents to AllArkive

You can drop any documents you already have — personal notes, technical
write-ups, a copy of your team wiki, a folder of PDFs you've collected —
into AllArkive. Kiwix will serve them and the RAG layer can index them
alongside Wikipedia and the rest.

This page explains how, and a little of how ZIM works so the workflow
makes sense.

---

## What is a ZIM file

ZIM is openZIM's container format — a single, compressed, indexed file
designed for offline random-access reads of web-style content.

Mental model: think of it as a `.zip` with a built-in search engine and
an HTTP layer bolted on top.

Concretely, every `.zim` contains:

- a **header** and **MIME-type table** at the front;
- **URL and title pointer lists** so any article can be located in
  O(log n) without scanning the file;
- the actual pages, images, and assets, grouped into **clusters**
  compressed with **Zstandard** (older ZIMs use LZMA2). Cluster-level
  compression means a reader only decompresses the chunk it needs, not
  the whole archive;
- optional embedded **Xapian indexes** — one for titles, one for
  full-text. That index is what powers the search box in Kiwix.

A reader (`kiwix-serve`, `kiwix-desktop`, anything using `libzim`)
memory-maps the file, jumps to the cluster offset for the requested
page, decompresses just that cluster, and serves it. That is why a
100 GB Wikipedia ZIM on a USB SSD feels responsive on a Raspberry Pi.

You do not need to know any of this to use AllArkive. It's useful
context for understanding why ZIM is a sensible format to put your own
documents into: one file, portable, compressed, searchable, with no
runtime dependency beyond a reader.

---

## When to make your own ZIM

You probably want a custom ZIM if:

- you have a directory of documents (markdown, docx, txt, html, …) and
  want them browsable and searchable from Kiwix;
- you want those documents available to the local LLM as a retrieval
  source, with citations;
- you want the result to be a single portable file you can copy to
  another machine, another Pi, a thumb drive, etc.

You probably do **not** need a ZIM if:

- you just want to read the files yourself — keep them as files;
- you want to mirror an entire external website — see "Mirroring a
  website" below, which uses a different tool (`zimit`).

---

## The fast path: `scripts/make-zim.sh`

We ship a wrapper that handles the whole pipeline for you. It uses
**Docker images for pandoc and zimwriterfs** — nothing is installed on
the host beyond Docker, which AllArkive already requires.

### Minimal example

You have a folder `~/notes/` full of markdown files:

```bash
scripts/make-zim.sh \
  --src   ~/notes \
  --name  my-notes \
  --title "My personal notes"
```

What happens:

1. Files are staged into a temp directory (your source tree is not
   touched).
2. Any `.md`, `.markdown`, `.rst`, `.docx`, `.odt`, `.txt`, `.tex`
   files are converted to `.html` via pandoc.
3. If no `index.html` exists, one is generated listing every page.
4. `zimwriterfs` builds `out/my-notes.zim`, including a Xapian
   full-text index.
5. The script prints the file size and its SHA-256.

### Install it into the running stack

Add `--install` to copy the ZIM into the ZIM directory and restart
Kiwix so it picks up the new file. Add `--reindex` to also rebuild the
RAG vector index so the local LLM can cite from your documents.

```bash
scripts/make-zim.sh \
  --src   ~/notes \
  --name  my-notes \
  --title "My personal notes" \
  --reindex
```

After it finishes:

- Kiwix serves it at `http://127.0.0.1:8081/` alongside the other ZIMs.
- The RAG model can cite your documents in answers.

### Useful options

| Flag | Purpose |
|---|---|
| `--description "<…>"` | Short description shown in Kiwix. |
| `--creator "<…>"` | Author name embedded in the ZIM metadata. |
| `--publisher "<…>"` | Publisher name (default: `self`). |
| `--language <code>` | ISO 639-3 language code. Default `eng`. |
| `--welcome <file>` | Welcome page relative to `--src`. Defaults to `index.html`; auto-generated if missing. |
| `--out <dir>` | Where to write the `.zim`. Default `./out/`. |
| `--install` | Copy the ZIM into the ZIM dir + restart Kiwix. |
| `--reindex` | Implies `--install`. Also runs `scripts/reindex.sh`. |
| `--zim-dir <dir>` | Override the ZIM destination for `--install`. |

Run `scripts/make-zim.sh --help` for the full list.

### What gets converted, what doesn't

The script converts the following extensions to HTML via pandoc:

- `.md`, `.markdown`, `.rst`
- `.docx`, `.odt`
- `.txt`, `.tex`

Already-HTML files pass through untouched. **PDFs are kept as-is** —
Kiwix will serve them as downloads but the embedded Xapian index will
not index their text. If you want PDFs searchable, convert them to
HTML first (e.g. with `pdftotext -layout your.pdf - | pandoc -o
your.html`) and place the HTML next to or instead of the PDF.

---

## Mirroring a website instead

If your "documents" are actually a website you want offline (a personal
wiki, a blog, a Confluence space you have access to), use **Zimit** —
the openZIM crawler that pairs Browsertrix Crawler with `warc2zim`. It
runs as a single Docker container and produces a `.zim` that drops into
the same ZIM directory.

```bash
docker run -v $(pwd)/out:/output \
  ghcr.io/openzim/zimit:2.1.6 \
  zimit \
    --seeds https://your-wiki.example.com \
    --name  your-wiki \
    --title "Your wiki (mirror)" \
    --description "Mirror captured on $(date -u +%F)"
```

Then copy `out/your-wiki.zim` into `$ALLARKIVE_DATA_DIR/zim/` and
restart Kiwix. `scripts/make-zim.sh` does not cover this case — Zimit
is the right tool.

---

## Doing it by hand (without our wrapper)

For completeness, the same workflow without the script. You need
`pandoc` and `zimwriterfs` available — either installed locally or via
the Docker images we use.

```bash
# 1. Convert any non-HTML inputs.
mkdir -p out/
pandoc --standalone notes.md -o out/notes.html

# 2. Make sure out/index.html exists and links to your pages.

# 3. Build the ZIM.
docker run --rm \
  -v "$(pwd)/out:/src:ro" \
  -v "$(pwd):/zimout" \
  ghcr.io/openzim/zim-tools:3.4.2 \
  zimwriterfs \
    --welcome=index.html \
    --language=eng \
    --title="My notes" \
    --description="Personal archive" \
    --creator="$USER" \
    --publisher=self \
    --name=my-notes \
    /src /zimout/my-notes.zim
```

---

## How the RAG layer finds your documents

Two layers, two indexes — worth keeping them straight:

1. **Kiwix layer**: the moment a `.zim` lands in the ZIM directory,
   Kiwix serves and searches it. The Xapian index is inside the ZIM
   itself. No extra step.
2. **RAG layer**: AllArkive maintains a separate vector index in
   `$ALLARKIVE_DATA_DIR/index/index.db`. It walks each ZIM, chunks
   article text, embeds it, and stores the vectors with the source URL
   as the citation. **A new ZIM is not searchable via the AI until you
   re-run the indexer.** `scripts/make-zim.sh --reindex` does this for
   you; otherwise run `scripts/reindex.sh`.

A note on coverage: large ZIMs are sampled per the article cap (see
`docs/TROUBLESHOOTING.md` on cap/coverage). Custom ZIMs are usually
small enough that every article gets indexed.

---

## License and trust reminders

Putting documents into a ZIM does not change their license. If you
plan to share the resulting `.zim` with anyone else:

- check the license of every document inside it (yours, third-party,
  AI-generated, mixed) — the `.zim` is a redistribution;
- include attribution where required (CC-BY, CC-BY-SA, etc.);
- if you're bundling third-party content as part of an AllArkive
  distribution, follow the per-bundle pattern in
  `bundles/<name>/LICENSE.md`.

If you're feeding documents into the RAG layer that you wouldn't trust
a stranger to have written, remember that the LLM will quote them back
to you confidently. The citation surface lets you check what the model
saw — use it. See `THREAT_MODEL.md` on poisoned content for the full
treatment.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `zimwriterfs` fails with "no welcome page found" | Your `--welcome` path doesn't resolve inside `--src`. Either pass `--welcome` explicitly or let the script auto-generate one. |
| ZIM builds but Kiwix doesn't list it | The container caches the ZIM list at startup. Restart `kiwix`: `docker compose restart kiwix`. |
| ZIM is listed but search returns nothing | Xapian index inside the ZIM might be empty (no HTML pages — only PDFs / images). Convert source documents to HTML before building. |
| Local LLM doesn't cite the new content | Run `scripts/reindex.sh`. The Kiwix-side index is separate from the RAG vector index. |
| `pandoc/minimal` or `zim-tools` image pull fails | You're offline. Pre-pull the images on a connected machine and `docker save` / `docker load` across, or override via `PANDOC_IMAGE` / `ZIMTOOLS_IMAGE` env vars to a local registry. |
