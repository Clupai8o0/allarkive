# AllArkive bundles

A bundle is a curated set of ZIM files — offline knowledge archives in
Kiwix's packaged format. This page describes the three bundles included
with AllArkive v0.1, their contents, sizes, and license obligations.

---

## Choosing a bundle

| Bundle | Use case | ZIM disk | + model | Total |
|--------|----------|----------|---------|-------|
| `minimal` | Pi 4, low-disk machines, testing | ~4 GB | ~2–4 GB | ~6–8 GB |
| `balanced` | Daily-use laptop (recommended) | ~33 GB | ~4 GB | ~37 GB |
| `comprehensive` | Large-disk machines, full research | 150+ GB | ~4 GB | 155+ GB |

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

**Good for**: most laptop and server installs. A full English reference library
that fits on a modern laptop.

| Source | Type | Approx size | License |
|--------|------|------------|---------|
| Wikipedia (English, text only) | General encyclopaedia | ~22 GB | CC-BY-SA 4.0 |
| WikiMed — medical reference (English) | Medical reference wiki | ~500 MB | CC-BY-SA 4.0 |
| iFixit — repair guides (English) | Repair and disassembly guides | ~3 GB | CC-BY-NC-SA 3.0 |
| Project Gutenberg (English) | Classic literature, public domain | ~5 GB | Public domain + various |
| SuperUser (Stack Exchange) | General tech Q&A | ~2 GB | CC-BY-SA 4.0 |

**Total ZIM size**: ~33 GB

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

**Good for**: users with 200+ GB free disk who want a full reference library
including Wikipedia with images, plus major Stack Exchange communities.

| Source | Type | Approx size | License |
|--------|------|------------|---------|
| Wikipedia (English, with images) | General encyclopaedia | ~85 GB | CC-BY-SA 4.0 |
| WikiMed — medical reference (English) | Medical reference wiki | ~500 MB | CC-BY-SA 4.0 |
| iFixit — repair guides (English) | Repair and disassembly guides | ~3 GB | CC-BY-NC-SA 3.0 |
| Project Gutenberg (English) | Classic literature, public domain | ~5 GB | Public domain + various |
| Stack Overflow | Programming Q&A | ~30 GB | CC-BY-SA 4.0 |
| SuperUser (Stack Exchange) | General tech Q&A | ~2 GB | CC-BY-SA 4.0 |
| Math Stack Exchange | Mathematics Q&A | ~3 GB | CC-BY-SA 4.0 |

**Total ZIM size**: ~128 GB

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

AllArkive does not restrict which ZIM files you use. To add a ZIM not in
a default bundle:

1. Download the ZIM from `https://download.kiwix.org/zim/` or another
   trusted source.
2. Verify the checksum manually:
   ```bash
   sha256sum your-file.zim
   # compare against the .sha256 file published alongside the download
   ```
3. Move the verified ZIM to `$ALLARKIVE_DATA_DIR/zim/`.
4. Restart kiwix-serve so it picks up the new file:
   ```bash
   docker compose restart kiwix
   ```
5. Re-run the RAG indexer so the new content is searchable via AI:
   ```bash
   docker compose exec rag python -m rag.index
   ```

**License reminder**: before adding a custom ZIM, confirm its license
permits your intended use. See the `THREAT_MODEL.md` section on custom
bundles and poisoned content.

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

The RAG indexer reads article text from each ZIM, generates embeddings,
and writes them to `$ALLARKIVE_DATA_DIR/index/index.db`. Approximate times
on a modern laptop CPU:

| Bundle | Index size | First-run index time |
|--------|-----------|---------------------|
| minimal | ~200 MB | ~5 minutes |
| balanced | ~1–2 GB | ~15–30 minutes |
| comprehensive | ~5–10 GB | ~2–4 hours |

The index persists across restarts. Re-indexing is only needed when ZIM
files change.

The `RAG_MAX_ARTICLES` setting in `compose/.env` caps articles indexed per
ZIM. The default (5000) keeps indexing time manageable. Increase it on
faster hardware with more time available.
