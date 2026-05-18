# AllArkive bundles

A bundle is a set of ZIM files — offline knowledge archives in Kiwix's
packaged format. AllArkive ships three curated bundles (`minimal`,
`balanced`, `comprehensive`) and supports user-defined bundles via
`custom`. This page describes the contents, sizes, and license
obligations for each, plus the workflow for `custom`.

---

## Choosing a bundle

| Bundle | Use case | ZIM disk | + model | Total |
|--------|----------|----------|---------|-------|
| `minimal` | Pi 4, low-disk machines, testing | ~4 GB | ~2–4 GB | ~6–8 GB |
| `balanced` | Daily-use laptop (recommended) | ~23 GB | ~5 GB | ~28 GB |
| `comprehensive` | Large-disk machines, full research | ~330 GB | ~4 GB | ~335 GB |
| `custom` | Compose your own — any URL or Kiwix handle | varies | varies | varies |

All bundles run fully offline once installed. Updates require re-downloading
the relevant ZIM files.

---

## Fetching a bundle

```bash
./scripts/fetch-bundle.sh <bundle-name>
```

The script downloads each ZIM file listed in `bundles/<name>/manifest.json`,
verifies the SHA-256 checksum, and stops on any verification failure.
Do not proceed past a checksum failure — re-download the affected file.

For `custom`, pass one or more `--add <url|handle>` flags. See [Adding a
custom bundle](#adding-a-custom-bundle) below.

---

## The `minimal` bundle

**Good for**: Raspberry Pi 4, machines with less than 10 GB free, first-time
installs where you want a fast smoke test.

| Source | Type | Approx size | License |
|--------|------|------------|---------|
| WikiMed — medical reference (English) | Medical reference wiki | ~500 MB | CC-BY-SA 4.0 |
| iFixit — repair guides (English) | Repair and disassembly guides | ~3 GB | CC-BY-NC-SA 3.0 |

**Total ZIM size**: ~3.5 GB

**Recommended model**: `qwen2.5:3b` (fits in 4 GB RAM)

**Manifest**: `bundles/minimal/manifest.json`

### iFixit license note

iFixit guides are licensed under CC-BY-NC-SA 3.0, which prohibits commercial
use. AllArkive's personal-use, self-hosted context is within the non-commercial
terms. If you are deploying AllArkive in a commercial setting, consult the
iFixit terms before bundling.

---

## The `balanced` bundle

**Good for**: most laptop and server installs. Full English reference library
under 30 GB — fits on any modern laptop.

| Source | Type | Verified size | License |
|--------|------|--------------|---------|
| Wikipedia (English, mini — full text) | General encyclopaedia | 12 GB | CC-BY-SA 4.0 |
| WikiMed — medical reference (English) | Medical reference wiki | ~500 MB | CC-BY-SA 4.0 |
| iFixit — repair guides (English) | Repair and disassembly guides | 3.3 GB | CC-BY-NC-SA 3.0 |
| SuperUser (Stack Exchange) | General tech Q&A | 3.7 GB | CC-BY-SA 4.0 |
| Unix & Linux (Stack Exchange) | Unix/Linux Q&A | 1.2 GB | CC-BY-SA 4.0 |
| Ask Ubuntu (Stack Exchange) | Ubuntu Q&A | 2.6 GB | CC-BY-SA 4.0 |

**Total ZIM size**: ~23 GB  *(sizes verified from download.kiwix.org, 2026-05)*

The Wikipedia `mini` variant contains every article in full — it strips
decorative templates and infobox styling, not content. It is substantially
smaller than `nopic` (~48 GB) for this reason.

Project Gutenberg (`en_all`, ~200 GB) is **not** in this bundle — the full corpus is
~200 GB. It is included in the `comprehensive` bundle. You can also add it
manually as a custom ZIM (see the section below).

**Recommended model**: `qwen2.5:7b` (~4 GB, fits in 8 GB RAM)

**Manifest**: `bundles/balanced/manifest.json`

### Wikipedia text-only note

This bundle uses the "nopic" (no pictures) Wikipedia variant, which is
significantly smaller than the full archive while containing all article
text. If you want infobox images and diagrams, use the `comprehensive`
bundle instead.

### Project Gutenberg license note

Project Gutenberg hosts texts whose copyright has expired in the United
States (pre-1928 publication date is a common but not universal rule).
Some texts are contributed with explicit open licenses. License status
varies per text. The Gutenberg website documents this per item. AllArkive
ships the ZIM as-is; you are responsible for understanding the terms
applicable to specific texts you use.

---

## The `comprehensive` bundle

**Good for**: users with 350+ GB free disk who want a full reference library
including Wikipedia with images, the complete Project Gutenberg corpus, and
major Stack Exchange communities.

| Source | Type | Approx size | License |
|--------|------|------------|---------|
| Wikipedia (English, with images) | General encyclopaedia | ~85 GB | CC-BY-SA 4.0 |
| WikiMed — medical reference (English) | Medical reference wiki | ~500 MB | CC-BY-SA 4.0 |
| iFixit — repair guides (English) | Repair and disassembly guides | ~3 GB | CC-BY-NC-SA 3.0 |
| Project Gutenberg (English, full corpus) | Classic literature, public domain | ~200 GB | Public domain + various |
| Stack Overflow | Programming Q&A | ~30 GB | CC-BY-SA 4.0 |
| SuperUser (Stack Exchange) | General tech Q&A | ~2 GB | CC-BY-SA 4.0 |
| Math Stack Exchange | Mathematics Q&A | ~3 GB | CC-BY-SA 4.0 |

**Total ZIM size**: ~323 GB

The Gutenberg `en_all` ZIM (~200 GB) dominates the disk requirement. If you
want everything else without Gutenberg, use the `balanced` bundle and add
individual sources manually.

**Recommended model**: `qwen2.5:7b` on 16 GB RAM; `qwen2.5:14b` on 32+ GB
for better reasoning quality over large archives.

**Manifest**: `bundles/comprehensive/manifest.json`

---

## License summary

| Source | License | Commercial use | Attribution required |
|--------|---------|---------------|---------------------|
| Wikipedia | CC-BY-SA 4.0 | Yes | Yes (ShareAlike) |
| WikiMed | CC-BY-SA 4.0 | Yes | Yes (ShareAlike) |
| iFixit | CC-BY-NC-SA 3.0 | **No** | Yes (ShareAlike) |
| Project Gutenberg | Public domain / various | Per text | Per text |
| Stack Overflow | CC-BY-SA 4.0 | Yes | Yes (ShareAlike) |
| SuperUser | CC-BY-SA 4.0 | Yes | Yes (ShareAlike) |
| Math Stack Exchange | CC-BY-SA 4.0 | Yes | Yes (ShareAlike) |

AllArkive's glue code is AGPL-3.0. The bundled content keeps its own licenses.
Each bundle's license detail is in `bundles/<name>/LICENSE.md`.

---

## Adding a custom bundle

AllArkive does not restrict which ZIM files you use. There are three paths:

- **The `custom` bundle**, driven by `--add` flags. Recommended — uses
  the same verified download/checksum pipeline as the named bundles.
- **Build a ZIM from your own documents** (markdown notes, docx files, a
  folder of HTML, etc.): see [`custom-docs.md`](./custom-docs.md), which
  walks through the `scripts/make-zim.sh` wrapper.
- **Drop a ZIM in by hand** — copy the file into
  `$ALLARKIVE_DATA_DIR/zim/`, restart `kiwix`, re-run the indexer.

### Using `custom` with `--add`

Each `--add` takes a Kiwix library handle or a full URL.

```bash
# At install time, with bootstrap.sh
scripts/bootstrap.sh --bundle custom \
    --add wikipedia_en_simple_all_maxi_2026-03 \
    --add ifixit_en_all_2025-12

# Or after install, just to fetch
scripts/fetch-bundle.sh custom \
    --add https://download.kiwix.org/zim/other/foo.zim

# Re-running with --add appends to bundles/custom/manifest.json.
# Re-running without --add re-fetches whatever the manifest already lists.
scripts/fetch-bundle.sh custom
```

What the script does:

1. Calls `scripts/build-custom-manifest.py` with the `--add` specs.
2. For each spec, either uses the URL verbatim or resolves a Kiwix
   handle through the project-prefix → download-category map (Wikipedia
   → `/zim/wikipedia/`, Stack Exchange family → `/zim/stack_exchange/`,
   etc.).
3. HEADs the URL to populate approximate size, then writes/appends to
   `bundles/custom/manifest.json` (gitignored — per-user state).
4. Downloads + SHA-256 verifies each entry through the standard
   fetch-bundle path.

### Handles that don't resolve

If a handle's first segment isn't in the mapping table (rare science
wikis, project subdomains, etc.), the script errors out with a pointer
to [library.kiwix.org](https://library.kiwix.org/) so you can grab the
full URL. Either pass the URL, or extend
[`scripts/build-custom-manifest.py`](../../scripts/build-custom-manifest.py)
with the new prefix.

### Indexing a custom bundle

The RAG indexer doesn't care what bundle a ZIM came from — it walks
`$ALLARKIVE_DATA_DIR/zim/` and indexes everything it finds. After
adding ZIMs, either:

```bash
# Full reindex with the active profile
scripts/reindex.sh

# Or just the new ZIMs (the indexer skips already-indexed files)
docker compose exec rag python indexer.py
```

### License reminder

Before redistributing your custom bundle, fill out
`bundles/custom/LICENSE.md` with the per-archive license for everything
you added. The shipped file is a template. See `docs/THREAT_MODEL.md`
on custom bundles and poisoned content.

---

## Updating a bundle

ZIM files are periodically republished by the upstream projects. To update:

1. Edit `bundles/<name>/manifest.json` with the new filename and SHA-256.
2. Delete the old ZIM from `$ALLARKIVE_DATA_DIR/zim/`.
3. Re-run `./scripts/fetch-bundle.sh <name>`.
4. Re-index: `docker compose exec rag python -m rag.index`.

Bundle updates are noted in `CHANGELOG.md`.

---

## ZIM file sizes and indexing time

The RAG indexer reads article text from each ZIM, generates embeddings via
Ollama, and writes them to `$ALLARKIVE_DATA_DIR/index/index.db`.

Indexing time and index size depend on the **profile**
(`RAG_PROFILE=pi|laptop|workstation`). Full breakdown:
[`docs/rag-optimization.md`](../rag-optimization.md).

Approximate first-run times on a modern laptop CPU (no GPU) with the
`laptop` profile:

| Bundle | Index size (v0.2 laptop) | First-run index time |
|--------|-------------------------|----------------------|
| minimal | ~50 MB | ~1–3 minutes |
| balanced | ~400 MB–1 GB | ~10–25 minutes |
| comprehensive | ~3–5 GB | ~2–4 hours |

On a Raspberry Pi 5 with the `pi` profile (hybrid mode on, BM25
fallback for ZIMs ≥ 4 GB):

| Bundle | Index size (Pi profile) | First-run index time on Pi 5 |
|--------|-------------------------|------------------------------|
| minimal | ~50 MB | ~5–10 minutes |
| balanced | ~150–300 MB | ~30–60 minutes |
| comprehensive | ~200–400 MB | ~1–3 hours |

The index persists across restarts. Re-indexing is only needed when ZIM
files change, you switch profiles, or you bump `RAG_QUANTIZATION` /
`RAG_CHUNK_SIZE`.

The `RAG_MAX_ARTICLES` setting in `compose/.env` caps articles indexed
per ZIM. With the v0.2 pipeline the default is `0` (unlimited) on
non-Pi platforms; the Pi profile pairs `RAG_MAX_ARTICLES=0` with hybrid
mode so coverage stays complete via BM25 for big ZIMs.
