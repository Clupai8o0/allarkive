#!/usr/bin/env python3
"""
Index ZIM files into an sqlite-vec vector store for RAG retrieval.

Usage:
    python indexer.py [--zim-dir DIR] [--index-dir DIR] [--ollama-url URL]
                      [--embed-model MODEL] [--chunk-size N] [--max-articles N]
                      [--force]

Environment variable equivalents:
    ZIM_DIR, INDEX_DIR, OLLAMA_URL, EMBED_MODEL,
    RAG_MAX_ARTICLES

Idempotent: already-indexed ZIMs are skipped unless --force is passed.
"""

import argparse
import logging
import math
import os
import re
import sqlite3
import struct
import sys
from pathlib import Path

import httpx
import sqlite_vec
from bs4 import BeautifulSoup
from libzim.reader import Archive

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("rag.indexer")

_CHUNK_SIZE = 800
_CHUNK_OVERLAP = 100
_MAX_ARTICLES_DEFAULT = 5000
_COMMIT_EVERY = 50


def _parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Index ZIM files for AllArkive RAG.")
    p.add_argument("--zim-dir", default=os.environ.get("ZIM_DIR", "/data"))
    p.add_argument("--index-dir", default=os.environ.get("INDEX_DIR", "/index"))
    p.add_argument("--ollama-url", default=os.environ.get("OLLAMA_URL", "http://ollama:11434"))
    p.add_argument("--embed-model", default=os.environ.get("EMBED_MODEL", "nomic-embed-text"))
    p.add_argument("--chunk-size", type=int, default=_CHUNK_SIZE)
    p.add_argument(
        "--max-articles",
        type=int,
        default=int(os.environ.get("RAG_MAX_ARTICLES", _MAX_ARTICLES_DEFAULT)),
    )
    p.add_argument(
        "--force",
        action="store_true",
        help="Re-index ZIMs even if already indexed at the same mtime.",
    )
    return p.parse_args()


# ── Database ──────────────────────────────────────────────────────────────────

def _open_db(index_dir: str, embed_dim: int) -> sqlite3.Connection:
    path = Path(index_dir) / "index.db"
    conn = sqlite3.connect(str(path))
    conn.enable_load_extension(True)
    sqlite_vec.load(conn)
    conn.enable_load_extension(False)
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(f"""
        CREATE TABLE IF NOT EXISTS meta (
            key   TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS indexed_zims (
            zim_name     TEXT PRIMARY KEY,
            mtime        REAL NOT NULL,
            article_count INTEGER NOT NULL,
            indexed_at   TEXT NOT NULL
        );
        CREATE TABLE IF NOT EXISTS chunks (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            zim_name     TEXT NOT NULL,
            article_path TEXT NOT NULL,
            chunk_idx    INTEGER NOT NULL,
            title        TEXT,
            text         TEXT NOT NULL
        );
        CREATE VIRTUAL TABLE IF NOT EXISTS chunk_embeddings USING vec0(
            chunk_id  INTEGER PRIMARY KEY,
            embedding FLOAT[{embed_dim}]
        );
    """)
    conn.execute(
        "INSERT OR IGNORE INTO meta(key,value) VALUES ('embed_dim',?)",
        [str(embed_dim)],
    )
    conn.commit()
    return conn


def _stored_dim(conn: sqlite3.Connection) -> int:
    row = conn.execute("SELECT value FROM meta WHERE key='embed_dim'").fetchone()
    return int(row[0]) if row else 0


def _already_indexed(conn: sqlite3.Connection, zim_name: str, mtime: float) -> bool:
    row = conn.execute(
        "SELECT mtime FROM indexed_zims WHERE zim_name=?", [zim_name]
    ).fetchone()
    return bool(row and abs(row[0] - mtime) < 1.0)


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


# ── Text processing ───────────────────────────────────────────────────────────

def _html_to_text(html: str) -> str:
    soup = BeautifulSoup(html, "html.parser")
    for tag in soup.find_all(["nav", "aside", "footer", "script", "style"]):
        tag.decompose()
    for tag in soup.find_all(
        class_=re.compile(r"(toc|sidebar|navbox|reflist|mw-references|catlinks)", re.I)
    ):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


def _chunk(text: str, size: int, overlap: int) -> list[str]:
    result = []
    start = 0
    while start < len(text):
        piece = text[start : start + size].strip()
        if piece:
            result.append(piece)
        start += size - overlap
    return result


# ── Embedding ─────────────────────────────────────────────────────────────────

def _embed(text: str, ollama_url: str, model: str, client: httpx.Client) -> list[float]:
    r = client.post(
        f"{ollama_url}/api/embeddings",
        json={"model": model, "prompt": text},
        timeout=60.0,
    )
    r.raise_for_status()
    return r.json()["embedding"]


def _normalize(v: list[float]) -> list[float]:
    mag = math.sqrt(sum(x * x for x in v))
    return [x / mag for x in v] if mag else v


def _pack(v: list[float]) -> bytes:
    return struct.pack(f"{len(v)}f", *v)


# ── Per-ZIM indexing ─────────────────────────────────────────────────────────

def _index_zim(
    zim_path: Path,
    conn: sqlite3.Connection,
    ollama_url: str,
    embed_model: str,
    chunk_size: int,
    max_articles: int,
    force: bool,
) -> None:
    zim_name = zim_path.stem
    mtime = zim_path.stat().st_mtime

    if not force and _already_indexed(conn, zim_name, mtime):
        log.info("skip %s (unchanged)", zim_path.name)
        return

    log.info("indexing %s ...", zim_path.name)
    if force:
        _drop_zim(conn, zim_name)

    archive = Archive(str(zim_path))
    log.info("  %d entries in archive (max_articles=%d)", archive.entry_count, max_articles)

    articles_done = 0
    chunks_done = 0

    with httpx.Client() as client:
        for entry in archive:
            if articles_done >= max_articles:
                log.info("  reached max_articles limit")
                break

            if entry.is_redirect:
                continue

            try:
                item = entry.get_item()
                if "text/html" not in item.mimetype:
                    continue
                html = bytes(item.content).decode("utf-8", errors="replace")
            except Exception:
                continue

            title = entry.title or entry.path.rsplit("/", 1)[-1]
            text = _html_to_text(html)
            if len(text) < 50:
                continue

            pieces = _chunk(text, chunk_size, _CHUNK_OVERLAP)
            for idx, piece in enumerate(pieces):
                try:
                    emb = _embed(piece[:1000], ollama_url, embed_model, client)
                    emb = _normalize(emb)
                    emb_bytes = _pack(emb)
                except Exception as exc:
                    log.warning("  embed failed %s chunk %d: %s", entry.path, idx, exc)
                    continue

                cur = conn.execute(
                    "INSERT INTO chunks(zim_name,article_path,chunk_idx,title,text)"
                    " VALUES(?,?,?,?,?)",
                    [zim_name, entry.path, idx, title, piece],
                )
                conn.execute(
                    "INSERT INTO chunk_embeddings(chunk_id,embedding) VALUES(?,?)",
                    [cur.lastrowid, emb_bytes],
                )
                chunks_done += 1

            articles_done += 1
            if articles_done % _COMMIT_EVERY == 0:
                conn.commit()
                log.info("  %d articles / %d chunks", articles_done, chunks_done)

    conn.execute(
        "INSERT OR REPLACE INTO indexed_zims(zim_name,mtime,article_count,indexed_at)"
        " VALUES(?,?,?,datetime('now'))",
        [zim_name, mtime, articles_done],
    )
    conn.commit()
    log.info("done: %s → %d articles, %d chunks", zim_path.name, articles_done, chunks_done)


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    args = _parse_args()

    zim_dir = Path(args.zim_dir)
    if not zim_dir.is_dir():
        log.error("ZIM directory not found: %s", zim_dir)
        sys.exit(1)

    index_dir = Path(args.index_dir)
    index_dir.mkdir(parents=True, exist_ok=True)

    log.info("connecting to Ollama at %s ...", args.ollama_url)
    with httpx.Client() as client:
        try:
            client.get(f"{args.ollama_url}/api/version", timeout=10.0).raise_for_status()
        except Exception as exc:
            log.error("cannot reach Ollama: %s", exc)
            sys.exit(1)

        log.info("probing embedding model '%s' ...", args.embed_model)
        try:
            sample = _embed("hello", args.ollama_url, args.embed_model, client)
            embed_dim = len(sample)
            log.info("embedding dimension: %d", embed_dim)
        except Exception as exc:
            log.error("embedding probe failed: %s", exc)
            log.error("ensure the model is pulled: ollama pull %s", args.embed_model)
            sys.exit(1)

    conn = _open_db(str(index_dir), embed_dim)

    stored = _stored_dim(conn)
    if stored and stored != embed_dim:
        log.error(
            "dimension mismatch: index=%d model=%d — run with --force to rebuild",
            stored,
            embed_dim,
        )
        sys.exit(1)

    zim_files = sorted(zim_dir.glob("*.zim"))
    if not zim_files:
        log.warning("no .zim files in %s", zim_dir)
        sys.exit(0)

    log.info("found %d ZIM file(s)", len(zim_files))
    for zf in zim_files:
        _index_zim(
            zim_path=zf,
            conn=conn,
            ollama_url=args.ollama_url,
            embed_model=args.embed_model,
            chunk_size=args.chunk_size,
            max_articles=args.max_articles,
            force=args.force,
        )

    conn.close()
    log.info("indexing complete.")


if __name__ == "__main__":
    main()
