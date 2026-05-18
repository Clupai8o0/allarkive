#!/usr/bin/env python3
"""
Index ZIM files into an sqlite-vec vector store for RAG retrieval.

Schema v2 (v0.2) changes vs v1:
  - Offset-only chunk storage. ``chunks.text`` removed; the RAG server reads
    the chunk text from the ZIM at query time via ``(char_offset, char_len)``.
    Cuts index size by ~60% on Wikipedia-class archives.
  - int8 vector quantization is the new default
    (``RAG_QUANTIZATION=int8|float32``). 4x smaller vectors, <1 point MTEB
    recall drop on cosine-normalised models.
  - Batched async embeddings via Ollama's ``/api/embed`` (plural) endpoint.
    BATCH_SIZE chunks per HTTP round-trip — 10-30x faster on CPU.
  - lxml HTML parser (5–10x faster than html.parser).
  - Larger chunks (2000 chars default, was 800). Fewer rows, better recall.
  - Title-prefixed text before embedding.
  - Crash-resume via ``indexed_zims.last_entry_id`` + ``UNIQUE`` constraint
    on (zim_name, article_path, chunk_idx) with ON CONFLICT DO UPDATE.
  - Optional hybrid mode (``RAG_HYBRID=1``, ``RAG_HYBRID_THRESHOLD_GB=4``):
    ZIMs at/above the threshold are registered with ``mode='bm25'`` instead
    of dense-indexed; the server queries libzim's built-in Xapian index for
    them. Saves indexing time entirely on multi-100-GB ZIMs.
  - Profile presets (``RAG_PROFILE=pi|laptop|workstation``) bundle sensible
    defaults; individual env vars / CLI flags override.

Idempotent: a ZIM that's already indexed under the current config is
skipped. A mismatched ``meta`` table (schema_version, embed model, embed
dim, quantization, extractor_version) refuses to start — the indexer wants
``--force`` (or you can ``rm`` the index file) to rebuild deliberately.
"""

import argparse
import asyncio
import logging
import os
import random
import sqlite3
import sys
import time
from pathlib import Path
from typing import Any

import httpx
import sqlite_vec
from libzim.reader import Archive

import profiles
import quant
import textproc

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("rag.indexer")

SCHEMA_VERSION = 2
_MIN_CHUNK_CHARS = 30
_COMMIT_BATCHES = 4  # commit every N flushed batches


# ── Config resolution ────────────────────────────────────────────────────────


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Index ZIM files for AllArkive RAG.")
    p.add_argument("--zim-dir", default=os.environ.get("ZIM_DIR", "/data"))
    p.add_argument("--index-dir", default=os.environ.get("INDEX_DIR", "/index"))
    p.add_argument(
        "--ollama-url",
        default=os.environ.get("OLLAMA_URL", "http://ollama:11434"),
    )
    p.add_argument(
        "--profile",
        default=os.environ.get("RAG_PROFILE", profiles.DEFAULT_PROFILE),
        choices=sorted(profiles.PROFILES.keys()),
        help="Indexing profile preset (default: %(default)s). Sets chunk size, "
             "quantization, hybrid mode, and batch size unless overridden.",
    )
    p.add_argument("--embed-model", default=os.environ.get("EMBED_MODEL"))
    p.add_argument("--chunk-size", type=int, default=_int_env("RAG_CHUNK_SIZE"))
    p.add_argument("--chunk-overlap", type=int, default=_int_env("RAG_CHUNK_OVERLAP"))
    p.add_argument(
        "--quantization",
        default=os.environ.get("RAG_QUANTIZATION"),
        choices=quant.SUPPORTED_MODES,
        help="Vector storage format. int8 (default in pi/laptop profile) is 4x "
             "smaller than float32 with negligible recall impact.",
    )
    p.add_argument(
        "--batch-size",
        type=int,
        default=_int_env("RAG_BATCH_SIZE"),
        help="Chunks per /api/embed request.",
    )
    p.add_argument(
        "--hybrid",
        action="store_true",
        default=_bool_env("RAG_HYBRID"),
        help="Skip dense indexing for ZIMs at or above --hybrid-threshold-gb. "
             "The server queries libzim's Xapian index for those archives.",
    )
    p.add_argument(
        "--hybrid-threshold-gb",
        type=float,
        default=_float_env("RAG_HYBRID_THRESHOLD_GB"),
        help="ZIM size threshold for hybrid mode. 0 disables.",
    )
    p.add_argument(
        "--max-articles",
        type=int,
        default=int(os.environ.get("RAG_MAX_ARTICLES", "0")),
        help="Per-ZIM article cap. 0 = unlimited.",
    )
    p.add_argument(
        "--large-zim-gb",
        type=float,
        default=float(os.environ.get("RAG_LARGE_ZIM_GB", "0")),
        help="ZIMs at/above this size get --large-max-articles instead. "
             "0 = disabled; --hybrid supersedes this on large ZIMs.",
    )
    p.add_argument(
        "--large-max-articles",
        type=int,
        default=int(os.environ.get("RAG_LARGE_MAX_ARTICLES", "0")),
        help="Article cap for large ZIMs. 0 = unlimited.",
    )
    p.add_argument(
        "--force",
        action="store_true",
        help="Drop and re-index every ZIM, ignoring resume state.",
    )
    args = p.parse_args()
    _apply_profile_defaults(args)
    return args


def _int_env(name: str) -> int | None:
    v = os.environ.get(name)
    if v is None or v == "":
        return None
    try:
        return int(v)
    except ValueError:
        return None


def _float_env(name: str) -> float | None:
    v = os.environ.get(name)
    if v is None or v == "":
        return None
    try:
        return float(v)
    except ValueError:
        return None


def _bool_env(name: str) -> bool:
    return os.environ.get(name, "").lower() in ("1", "true", "yes", "on")


def _apply_profile_defaults(args: argparse.Namespace) -> None:
    """Fill any unset arg from the resolved profile."""
    prof = profiles.get(args.profile)
    if not args.embed_model:
        args.embed_model = prof["embed_model"]
    if args.chunk_size is None:
        args.chunk_size = prof["chunk_size"]
    if args.chunk_overlap is None:
        args.chunk_overlap = prof["chunk_overlap"]
    if not args.quantization:
        args.quantization = prof["quantization"]
    if args.batch_size is None:
        args.batch_size = prof["batch_size"]
    # --hybrid is a flag; respect the explicit form only if env didn't set it.
    if not _bool_env("RAG_HYBRID") and not args.hybrid:
        args.hybrid = prof["hybrid"]
    if args.hybrid_threshold_gb is None:
        args.hybrid_threshold_gb = prof["hybrid_threshold_gb"]


# ── Database ──────────────────────────────────────────────────────────────────


def _open_db(index_dir: str, embed_dim: int, args: argparse.Namespace) -> sqlite3.Connection:
    """Open (or create) the index DB and verify it matches the current config.

    Mismatched schema_version, embed_model, embed_dim, quantization, or
    extractor_version refuses with a clear error pointing at ``reindex.sh``.
    Passing ``--force`` wipes the file and rebuilds.
    """
    path = Path(index_dir) / "index.db"
    if args.force and path.exists():
        log.info("--force: removing existing index at %s", path)
        path.unlink()

    conn = sqlite3.connect(str(path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA synchronous=NORMAL")
    conn.execute("PRAGMA temp_store=MEMORY")
    conn.executescript(f"""
        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS indexed_zims (
            zim_name      TEXT PRIMARY KEY,
            mtime         REAL NOT NULL,
            article_count INTEGER NOT NULL DEFAULT 0,
            chunk_count   INTEGER NOT NULL DEFAULT 0,
            last_entry_id INTEGER NOT NULL DEFAULT -1,
            mode          TEXT NOT NULL DEFAULT 'dense',
            indexed_at    TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            zim_name     TEXT NOT NULL,
            article_path TEXT NOT NULL,
            chunk_idx    INTEGER NOT NULL,
            title        TEXT,
            char_offset  INTEGER NOT NULL,
            char_len     INTEGER NOT NULL,
            UNIQUE(zim_name, article_path, chunk_idx)
        );
        CREATE INDEX IF NOT EXISTS idx_chunks_zim ON chunks(zim_name);
    """)
    conn.execute(
        f"CREATE VIRTUAL TABLE IF NOT EXISTS chunk_embeddings USING vec0("
        f"chunk_id INTEGER PRIMARY KEY, embedding {quant.vec_column_sql(args.quantization, embed_dim)})"
    )

    _verify_or_seed_meta(conn, embed_dim, args)
    return conn


def _verify_or_seed_meta(
    conn: sqlite3.Connection, embed_dim: int, args: argparse.Namespace
) -> None:
    expected = {
        "schema_version": str(SCHEMA_VERSION),
        "extractor_version": str(textproc.EXTRACTOR_VERSION),
        "embed_dim": str(embed_dim),
        "embed_model": args.embed_model,
        "quantization": args.quantization,
        "chunk_size": str(args.chunk_size),
        "chunk_overlap": str(args.chunk_overlap),
    }
    existing = dict(conn.execute("SELECT key, value FROM meta").fetchall())
    if not existing:
        for k, v in expected.items():
            conn.execute(
                "INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", [k, str(v)]
            )
        conn.commit()
        return

    mismatches = [
        (k, existing.get(k), v)
        for k, v in expected.items()
        if k in existing and existing[k] != str(v)
    ]
    if mismatches:
        log.error("Index meta mismatch — current config is incompatible with this index:")
        for k, was, now in mismatches:
            log.error("  %-18s indexed=%-30s current=%s", k, was, now)
        log.error(
            "Reindex with `scripts/reindex.sh --force` or remove %s/index.db and retry.",
            args.index_dir,
        )
        sys.exit(2)
    # New keys (e.g. added in a minor version): record them silently.
    for k, v in expected.items():
        if k not in existing:
            conn.execute(
                "INSERT OR REPLACE INTO meta(key,value) VALUES(?,?)", [k, str(v)]
            )
    conn.commit()


def _drop_zim(conn: sqlite3.Connection, zim_name: str) -> None:
    ids = [
        r[0]
        for r in conn.execute("SELECT id FROM chunks WHERE zim_name=?", [zim_name])
    ]
    if ids:
        ph = ",".join("?" * len(ids))
        conn.execute(f"DELETE FROM chunk_embeddings WHERE chunk_id IN ({ph})", ids)
        conn.execute("DELETE FROM chunks WHERE zim_name=?", [zim_name])
    conn.execute("DELETE FROM indexed_zims WHERE zim_name=?", [zim_name])
    conn.commit()


def _record_progress(
    conn: sqlite3.Connection,
    zim_name: str,
    mtime: float,
    articles: int,
    chunks: int,
    last_entry_id: int,
    mode: str = "dense",
) -> None:
    conn.execute(
        "INSERT INTO indexed_zims(zim_name, mtime, article_count, chunk_count, last_entry_id, mode, indexed_at)"
        " VALUES(?,?,?,?,?,?,datetime('now'))"
        " ON CONFLICT(zim_name) DO UPDATE SET"
        "   mtime=excluded.mtime,"
        "   article_count=excluded.article_count,"
        "   chunk_count=excluded.chunk_count,"
        "   last_entry_id=excluded.last_entry_id,"
        "   mode=excluded.mode,"
        "   indexed_at=excluded.indexed_at",
        [zim_name, mtime, articles, chunks, last_entry_id, mode],
    )
    conn.commit()


# ── Ollama embedding ─────────────────────────────────────────────────────────


async def _embed_one(
    text: str, client: httpx.AsyncClient, url: str, model: str
) -> list[float]:
    r = await client.post(
        f"{url}/api/embed",
        json={"model": model, "input": text},
        timeout=120.0,
    )
    r.raise_for_status()
    data = r.json()
    embs = data.get("embeddings") or [data.get("embedding")]
    if not embs or embs[0] is None:
        raise RuntimeError(f"empty embedding response: {data!r}")
    return embs[0]


async def _embed_batch(
    texts: list[str],
    client: httpx.AsyncClient,
    url: str,
    model: str,
) -> list[list[float]]:
    """Send a batch to ``/api/embed`` (plural). Falls back to per-item on error."""
    if not texts:
        return []
    try:
        r = await client.post(
            f"{url}/api/embed",
            json={"model": model, "input": texts},
            timeout=300.0,
        )
        r.raise_for_status()
        data = r.json()
        embs = data.get("embeddings")
        if isinstance(embs, list) and len(embs) == len(texts):
            return embs
        log.warning("batch embed response shape unexpected: %s", list(data.keys()))
    except Exception as exc:
        log.warning("batch embed failed (%s) — falling back to per-item", exc)

    # Fallback: serial single-input requests. Slower but resilient.
    results: list[list[float]] = []
    for t in texts:
        try:
            results.append(await _embed_one(t, client, url, model))
        except Exception as exc:
            log.warning("single embed failed: %s — dropping", exc)
            results.append([])
    return results


# ── Per-ZIM indexing ─────────────────────────────────────────────────────────


def _effective_limit(
    zim_path: Path,
    max_articles: int,
    large_zim_gb: float,
    large_max_articles: int,
) -> int:
    """Article limit for this ZIM. 0 means unlimited."""
    if large_zim_gb > 0:
        size_gb = zim_path.stat().st_size / 1e9
        if size_gb >= large_zim_gb:
            return large_max_articles
        return 0
    return max_articles


def _pick_entry_ids(archive: Archive, limit: int, resume_from: int) -> list[int]:
    """Choose the order in which to scan entries.

    Sequential when uncapped (better I/O locality). Random sample when
    capped — but oversampled to compensate for redirect/non-html skip rate.
    Resume picks up where we left off when iterating sequentially.
    """
    total = archive.all_entry_count
    if limit <= 0:
        start = max(0, resume_from + 1)
        return list(range(start, total))
    # Random sample, oversampled 1.5x to absorb redirect filtering.
    sample_size = min(total, int(limit * 1.5) + 1)
    return random.sample(range(total), sample_size)


async def _flush_batch(
    batch: list[dict[str, Any]],
    conn: sqlite3.Connection,
    client: httpx.AsyncClient,
    args: argparse.Namespace,
) -> int:
    """Embed and insert one batch. Returns the number of chunks committed."""
    if not batch:
        return 0
    texts = [it["embed_text"] for it in batch]
    embeddings = await _embed_batch(texts, client, args.ollama_url, args.embed_model)
    inserted = 0
    for it, emb in zip(batch, embeddings):
        if not emb:
            continue
        emb = quant.normalize(emb)
        packed = quant.pack(emb, args.quantization)
        if quant.degenerate(emb, packed, args.quantization):
            log.warning(
                "skip %s chunk %d: degenerate embedding",
                it["article_path"], it["chunk_idx"],
            )
            continue
        try:
            row = conn.execute(
                "INSERT INTO chunks"
                " (zim_name, article_path, chunk_idx, title, char_offset, char_len)"
                " VALUES(?,?,?,?,?,?)"
                " ON CONFLICT(zim_name, article_path, chunk_idx)"
                "   DO UPDATE SET title=excluded.title,"
                "                 char_offset=excluded.char_offset,"
                "                 char_len=excluded.char_len"
                " RETURNING id",
                [
                    it["zim_name"],
                    it["article_path"],
                    it["chunk_idx"],
                    it["title"],
                    it["char_offset"],
                    it["char_len"],
                ],
            ).fetchone()
            chunk_id = row[0]
            conn.execute(
                "DELETE FROM chunk_embeddings WHERE chunk_id=?", [chunk_id]
            )
            conn.execute(
                "INSERT INTO chunk_embeddings(chunk_id, embedding) VALUES(?,?)",
                [chunk_id, packed],
            )
            inserted += 1
        except sqlite3.OperationalError as exc:
            log.warning(
                "sqlite-vec rejected %s chunk %d: %s — skipping",
                it["article_path"], it["chunk_idx"], exc,
            )
            conn.rollback()
            continue
    return inserted


async def _index_zim_dense(
    zim_path: Path,
    conn: sqlite3.Connection,
    args: argparse.Namespace,
) -> None:
    zim_name = zim_path.stem
    mtime = zim_path.stat().st_mtime
    size_gb = round(zim_path.stat().st_size / 1e9, 1)

    limit = _effective_limit(
        zim_path, args.max_articles, args.large_zim_gb, args.large_max_articles,
    )
    limit_str = "unlimited" if limit <= 0 else str(limit)

    # Skip-or-re-index decision.
    archive = Archive(str(zim_path))
    total_entries = archive.all_entry_count

    resume_from = -1
    if not args.force:
        prev = conn.execute(
            "SELECT mtime, article_count, last_entry_id, mode FROM indexed_zims WHERE zim_name=?",
            [zim_name],
        ).fetchone()
        if prev:
            prev_mtime, prev_count, prev_last_id, prev_mode = prev
            if prev_mode != "dense":
                _drop_zim(conn, zim_name)
            elif abs(prev_mtime - mtime) < 1.0:
                prev_was_capped = prev_count < total_entries
                new_allows_more = limit == 0 or limit > prev_count
                if not (prev_was_capped and new_allows_more):
                    log.info("skip %s (already indexed, cap satisfied)", zim_path.name)
                    return
                # Mid-run resume: keep existing rows, continue from last_entry_id.
                if limit <= 0 and prev_last_id >= 0:
                    resume_from = prev_last_id
                    log.info(
                        "resuming %s from entry id %d (had %d articles)",
                        zim_path.name, prev_last_id, prev_count,
                    )
                else:
                    log.info(
                        "re-indexing %s: cap raised %d → %s",
                        zim_path.name, prev_count,
                        "unlimited" if limit <= 0 else str(limit),
                    )
                    _drop_zim(conn, zim_name)

    log.info(
        "indexing %s (%.1f GB, limit=%s, profile=%s, quant=%s, chunk=%d, batch=%d)",
        zim_path.name, size_gb, limit_str, args.profile,
        args.quantization, args.chunk_size, args.batch_size,
    )

    entry_ids = _pick_entry_ids(archive, limit, resume_from)

    articles_done = 0
    chunks_done = 0
    batches_since_commit = 0
    last_id = resume_from
    started = time.monotonic()

    buffer: list[dict[str, Any]] = []
    async with httpx.AsyncClient() as client:
        for i in entry_ids:
            if 0 < limit <= articles_done:
                break

            entry = _safe_get_entry(archive, i)
            if entry is None or entry.is_redirect:
                last_id = i
                continue

            try:
                item = entry.get_item()
                if "text/html" not in item.mimetype:
                    last_id = i
                    continue
                html = bytes(item.content).decode("utf-8", errors="replace")
            except Exception:
                last_id = i
                continue

            title = entry.title or entry.path.rsplit("/", 1)[-1]
            text = textproc.html_to_text(html)
            if len(text) < 50:
                last_id = i
                continue

            spans = textproc.chunk_offsets(len(text), args.chunk_size, args.chunk_overlap)
            for chunk_idx, (start, end) in enumerate(spans):
                piece = text[start:end].strip()
                if len(piece) < _MIN_CHUNK_CHARS:
                    continue
                buffer.append({
                    "zim_name": zim_name,
                    "article_path": entry.path,
                    "chunk_idx": chunk_idx,
                    "title": title,
                    "char_offset": start,
                    "char_len": end - start,
                    "embed_text": textproc.title_prefixed(title, piece),
                })

            articles_done += 1
            last_id = i

            while len(buffer) >= args.batch_size:
                head = buffer[: args.batch_size]
                buffer = buffer[args.batch_size :]
                n = await _flush_batch(head, conn, client, args)
                chunks_done += n
                batches_since_commit += 1
                if batches_since_commit >= _COMMIT_BATCHES:
                    _record_progress(
                        conn, zim_name, mtime, articles_done, chunks_done,
                        last_id, mode="dense",
                    )
                    elapsed = time.monotonic() - started
                    rate = articles_done / elapsed if elapsed > 0 else 0
                    log.info(
                        "  %d articles / %d chunks (%.1f art/s)",
                        articles_done, chunks_done, rate,
                    )
                    batches_since_commit = 0

        # drain remainder
        while buffer:
            head = buffer[: args.batch_size]
            buffer = buffer[args.batch_size :]
            n = await _flush_batch(head, conn, client, args)
            chunks_done += n

    _record_progress(
        conn, zim_name, mtime, articles_done, chunks_done, last_id, mode="dense",
    )
    elapsed = time.monotonic() - started
    log.info(
        "done: %s → %d articles, %d chunks in %.0fs (limit was %s)",
        zim_path.name, articles_done, chunks_done, elapsed, limit_str,
    )


def _index_zim_bm25(
    zim_path: Path,
    conn: sqlite3.Connection,
) -> None:
    """Register a ZIM as BM25-only — no chunks, no embeddings.

    The server queries this archive at request time using libzim's Searcher
    (the ZIM's built-in Xapian full-text index). Saves the entire dense
    indexing pass for multi-100-GB ZIMs.
    """
    zim_name = zim_path.stem
    mtime = zim_path.stat().st_mtime
    # Drop any prior dense rows so the server doesn't double-count.
    _drop_zim(conn, zim_name)
    _record_progress(
        conn, zim_name, mtime, articles=0, chunks=0, last_entry_id=-1, mode="bm25",
    )
    log.info("registered %s as BM25-only (hybrid mode)", zim_path.name)


def _safe_get_entry(archive: Archive, entry_id: int):
    try:
        return archive._get_entry_by_id(entry_id)
    except Exception:
        return None


# ── Entry point ───────────────────────────────────────────────────────────────


async def _amain(args: argparse.Namespace) -> int:
    zim_dir = Path(args.zim_dir)
    if not zim_dir.is_dir():
        log.error("ZIM directory not found: %s", zim_dir)
        return 1

    index_dir = Path(args.index_dir)
    index_dir.mkdir(parents=True, exist_ok=True)

    log.info("profile=%s embed=%s quant=%s chunk=%d batch=%d hybrid=%s",
             args.profile, args.embed_model, args.quantization,
             args.chunk_size, args.batch_size, args.hybrid)

    log.info("connecting to Ollama at %s ...", args.ollama_url)
    async with httpx.AsyncClient() as client:
        try:
            r = await client.get(f"{args.ollama_url}/api/version", timeout=10.0)
            r.raise_for_status()
        except Exception as exc:
            log.error("cannot reach Ollama: %s", exc)
            return 1
        log.info("probing embedding model '%s' ...", args.embed_model)
        try:
            sample = await _embed_one("hello", client, args.ollama_url, args.embed_model)
            embed_dim = len(sample)
            log.info("embedding dimension: %d", embed_dim)
        except Exception as exc:
            log.error("embedding probe failed: %s", exc)
            log.error("pull the model: ollama pull %s", args.embed_model)
            return 1

    conn = _open_db(str(index_dir), embed_dim, args)

    zim_files = sorted(zim_dir.glob("*.zim"))
    if not zim_files:
        log.warning("no .zim files in %s", zim_dir)
        return 0

    log.info("found %d ZIM file(s)", len(zim_files))
    if args.hybrid and args.hybrid_threshold_gb > 0:
        log.info(
            "hybrid mode ON: ZIMs ≥ %.1f GB will be registered for BM25 only",
            args.hybrid_threshold_gb,
        )

    for zf in zim_files:
        size_gb = zf.stat().st_size / 1e9
        if args.hybrid and args.hybrid_threshold_gb > 0 and size_gb >= args.hybrid_threshold_gb:
            _index_zim_bm25(zf, conn)
        else:
            await _index_zim_dense(zf, conn, args)

    conn.close()
    log.info("indexing complete.")
    return 0


def main() -> None:
    args = _parse_args()
    rc = asyncio.run(_amain(args))
    sys.exit(rc)


if __name__ == "__main__":
    main()
