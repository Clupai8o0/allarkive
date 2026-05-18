#!/usr/bin/env python3
"""
AllArkive RAG service — OpenAI-compatible API.

Sits between Open WebUI and Ollama. Every query is answered with retrieved
passages from the sqlite-vec index or refused with a no-sources message.

Schema v2 (v0.2) changes vs v1:
  - Chunk text is no longer stored in the DB. The server reads it from the
    backing ZIM at request time using ``(article_path, char_offset, char_len)``
    and the shared :mod:`textproc` extractor. Verifies extractor_version on
    startup; mismatched indexes refuse to start (point at ``reindex.sh``).
  - Vector quantization: query embeddings are packed in the same mode the
    index was built with (``int8`` by default; ``float32`` supported).
  - Hybrid retrieval: ZIMs registered with ``mode='bm25'`` (large archives
    skipped at index time) are queried via libzim's built-in Xapian index
    and reciprocal-rank-fusion-merged with the dense top-K.

Environment variables (see compose/.env.example for the full list):
    OLLAMA_URL          http://ollama:11434
    INDEX_DIR           /index
    ZIM_DIR             /data
    KIWIX_PUBLIC_URL    http://127.0.0.1:8081
    EMBED_MODEL         (read from index meta on startup; env wins if set)
    CHAT_MODEL          qwen2.5:7b
    RAG_TOP_K           5
    RAG_MAX_DISTANCE    1.0  (lower = more similar; L2 on unit vectors)
    RAG_BM25_K          5    (BM25 candidates per BM25 ZIM)
"""

import json
import logging
import math
import os
import sqlite3
import time
import uuid
from functools import lru_cache
from pathlib import Path
from typing import Any

import httpx
import sqlite_vec
from fastapi import FastAPI, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

import quant
import textproc
from citations import rewrite_citations
from prompt import NO_SOURCES_TEXT, build_system_prompt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("rag.server")

_OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama:11434")
_INDEX_DIR = os.environ.get("INDEX_DIR", "/index")
_ZIM_DIR = os.environ.get("ZIM_DIR", "/data")
_KIWIX_PUBLIC_URL = os.environ.get("KIWIX_PUBLIC_URL", "http://127.0.0.1:8081")
_WEBUI_PUBLIC_URL = os.environ.get("WEBUI_PUBLIC_URL", "http://127.0.0.1:3000")
_CHAT_MODEL = os.environ.get("CHAT_MODEL", "qwen2.5:7b")
_SEARCH_ONLY = _CHAT_MODEL in ("", "__none__")
_TOP_K = int(os.environ.get("RAG_TOP_K", "5"))
_BM25_K = int(os.environ.get("RAG_BM25_K", "5"))
_MAX_DIST = float(os.environ.get("RAG_MAX_DISTANCE", "1.0"))
_INDEX_PATH = str(Path(_INDEX_DIR) / "index.db")

# Set from meta on first DB open; env override wins.
_EMBED_MODEL = os.environ.get("EMBED_MODEL", "")
_QUANTIZATION = "int8"
_EMBED_DIM = 0

_db: sqlite3.Connection | None = None
_meta: dict[str, str] = {}


# ── DB ───────────────────────────────────────────────────────────────────────


def _get_db() -> sqlite3.Connection:
    global _db, _meta, _EMBED_MODEL, _QUANTIZATION, _EMBED_DIM
    if _db is None:
        if not Path(_INDEX_PATH).exists():
            raise RuntimeError(
                f"Vector index not found at {_INDEX_PATH}. "
                "Run: docker compose exec rag python indexer.py"
            )
        uri = f"file:{_INDEX_PATH}?mode=ro"
        _db = sqlite3.connect(uri, uri=True, check_same_thread=False)
        _db.execute("PRAGMA busy_timeout=30000")
        _db.enable_load_extension(True)
        sqlite_vec.load(_db)
        _db.enable_load_extension(False)

        _meta = dict(_db.execute("SELECT key, value FROM meta").fetchall())

        schema = _meta.get("schema_version")
        if schema != "2":
            raise RuntimeError(
                f"Incompatible index schema_version={schema!r}; this server "
                "expects schema_version=2. Run: scripts/reindex.sh --force"
            )

        extractor = _meta.get("extractor_version")
        if extractor != str(textproc.EXTRACTOR_VERSION):
            raise RuntimeError(
                f"Index extractor_version={extractor!r} but server is "
                f"{textproc.EXTRACTOR_VERSION}. Run: scripts/reindex.sh --force"
            )

        if not _EMBED_MODEL:
            _EMBED_MODEL = _meta.get("embed_model", "nomic-embed-text")
        _QUANTIZATION = _meta.get("quantization", "int8")
        try:
            _EMBED_DIM = int(_meta.get("embed_dim", "0"))
        except ValueError:
            _EMBED_DIM = 0

        log.info(
            "index loaded: embed=%s dim=%d quant=%s",
            _EMBED_MODEL, _EMBED_DIM, _QUANTIZATION,
        )
    return _db


# ── ZIM archive cache ────────────────────────────────────────────────────────


@lru_cache(maxsize=32)
def _open_archive(zim_name: str):
    """Open and cache a libzim Archive. One open per ZIM for the process lifetime."""
    from libzim.reader import Archive

    path = Path(_ZIM_DIR) / f"{zim_name}.zim"
    if not path.exists():
        raise FileNotFoundError(f"ZIM not found: {path}")
    return Archive(str(path))


def _read_article_text(zim_name: str, article_path: str) -> str | None:
    """Return the cleaned article text from a ZIM, or None on failure."""
    try:
        archive = _open_archive(zim_name)
        entry = archive.get_entry_by_path(article_path)
        if entry.is_redirect:
            entry = entry.get_redirect_entry()
        item = entry.get_item()
        if "text/html" not in item.mimetype:
            return None
        html = bytes(item.content).decode("utf-8", errors="replace")
        return textproc.html_to_text(html)
    except Exception as exc:
        log.warning("failed to read %s/%s: %s", zim_name, article_path, exc)
        return None


# ── Embedding ────────────────────────────────────────────────────────────────


def _embed_query(text: str) -> list[float]:
    with httpx.Client() as client:
        r = client.post(
            f"{_OLLAMA_URL}/api/embed",
            json={"model": _EMBED_MODEL, "input": text},
            timeout=60.0,
        )
        r.raise_for_status()
        data = r.json()
    embs = data.get("embeddings") or [data.get("embedding")]
    if not embs or embs[0] is None:
        raise RuntimeError(f"empty embedding response: {list(data.keys())}")
    return quant.normalize(embs[0])


# ── Retrieval ────────────────────────────────────────────────────────────────


def _dense_search(query_vec: bytes, k: int) -> list[dict]:
    db = _get_db()
    rows = db.execute(
        """
        WITH knn AS (
            SELECT chunk_id, distance
            FROM   chunk_embeddings
            WHERE  embedding MATCH ?
            AND    k = ?
        )
        SELECT c.zim_name, c.article_path, c.title, c.char_offset, c.char_len, knn.distance
        FROM   knn
        JOIN   chunks c ON c.id = knn.chunk_id
        ORDER  BY knn.distance
        """,
        [query_vec, k],
    ).fetchall()
    out = []
    for r in rows:
        if r[5] > _MAX_DIST:
            continue
        out.append({
            "zim_name": r[0],
            "article_path": r[1],
            "title": r[2] or r[1].rsplit("/", 1)[-1],
            "char_offset": r[3],
            "char_len": r[4],
            "distance": r[5],
            "source": "dense",
        })
    return out


def _bm25_search(query: str, k: int) -> list[dict]:
    """Run libzim's Xapian search across BM25-registered ZIMs."""
    db = _get_db()
    bm25_zims = [
        r[0]
        for r in db.execute(
            "SELECT zim_name FROM indexed_zims WHERE mode='bm25'"
        ).fetchall()
    ]
    if not bm25_zims:
        return []

    try:
        from libzim.search import Query, Searcher
    except Exception as exc:
        log.warning("libzim.search unavailable: %s", exc)
        return []

    out: list[dict] = []
    for zim_name in bm25_zims:
        try:
            archive = _open_archive(zim_name)
        except FileNotFoundError:
            continue
        try:
            searcher = Searcher(archive)
            q = Query().set_query(query)
            search = searcher.search(q)
            estimated = search.getEstimatedMatches()
            if estimated == 0:
                continue
            results = list(search.getResults(0, k))
            for rank, path in enumerate(results):
                out.append({
                    "zim_name": zim_name,
                    "article_path": path,
                    "title": path.rsplit("/", 1)[-1].replace("_", " "),
                    "char_offset": 0,
                    "char_len": 0,           # 0 = read full article and clip later
                    "bm25_rank": rank,
                    "source": "bm25",
                })
        except Exception as exc:
            log.warning("bm25 search on %s failed: %s", zim_name, exc)
            continue
    return out


def _rrf_merge(
    dense: list[dict], bm25: list[dict], k_constant: int = 60
) -> list[dict]:
    """Reciprocal Rank Fusion: ``score = sum(1/(k + rank))`` over rankings.

    Dense results are ranked by distance (already sorted ascending). BM25
    results carry their own rank. We merge by (zim_name, article_path)
    keeping the best metadata per key.
    """
    scores: dict[tuple[str, str], float] = {}
    keep: dict[tuple[str, str], dict] = {}
    for rank, p in enumerate(dense):
        key = (p["zim_name"], p["article_path"])
        scores[key] = scores.get(key, 0.0) + 1.0 / (k_constant + rank)
        keep[key] = p
    for p in bm25:
        key = (p["zim_name"], p["article_path"])
        scores[key] = scores.get(key, 0.0) + 1.0 / (k_constant + p.get("bm25_rank", 0))
        keep.setdefault(key, p)
    fused = sorted(keep.values(), key=lambda p: -scores[(p["zim_name"], p["article_path"])])
    return fused


def _retrieve(query: str) -> list[dict]:
    emb = _embed_query(query)
    packed = quant.pack(emb, _QUANTIZATION)

    dense = _dense_search(packed, _TOP_K)
    bm25 = _bm25_search(query, _BM25_K)

    merged = _rrf_merge(dense, bm25) if bm25 else dense
    merged = merged[: _TOP_K]

    # Hydrate text lazily from the ZIM.
    passages: list[dict] = []
    for p in merged:
        text = _read_article_text(p["zim_name"], p["article_path"])
        if text is None:
            continue
        if p["char_len"] > 0:
            snippet = text[p["char_offset"] : p["char_offset"] + p["char_len"]].strip()
        else:
            # BM25 result — clip the article head to a chunk-sized window.
            snippet = text[:2000].strip()
        if not snippet:
            continue
        passages.append({
            "zim_name": p["zim_name"],
            "article_path": p["article_path"],
            "title": p["title"],
            "text": snippet,
            "distance": p.get("distance"),
            "source": p.get("source", "dense"),
        })
    return passages


# ── Response helpers ─────────────────────────────────────────────────────────


def _format_passages_as_citations(passages: list[dict], kiwix_public_url: str) -> str:
    base = kiwix_public_url.rstrip("/")
    lines = [
        "**Search results — top passages from the archive.** "
        "No chat model is configured (search-only mode), so these are the raw "
        "retrieved excerpts; click a citation to open the source article.",
        "",
    ]
    for n, p in enumerate(passages, start=1):
        title = p.get("title") or p["article_path"].rsplit("/", 1)[-1].replace("_", " ")
        url = f"{base}/{p['zim_name']}/{p['article_path']}"
        snippet = " ".join(p["text"].split())[:400]
        if len(p["text"]) > 400:
            snippet += "…"
        lines.append(f"[[{n}: {title}]]({url})")
        lines.append("")
        lines.append(snippet)
        lines.append("")
    return "\n".join(lines).rstrip()


def _call_ollama(messages: list[dict]) -> str:
    with httpx.Client() as client:
        r = client.post(
            f"{_OLLAMA_URL}/api/chat",
            json={"model": _CHAT_MODEL, "messages": messages, "stream": False},
            timeout=120.0,
        )
        r.raise_for_status()
    return r.json()["message"]["content"]


def _completion_event(comp_id: str, created: int, content: str, finish: str | None) -> str:
    payload = {
        "id": comp_id,
        "object": "chat.completion.chunk",
        "created": created,
        "model": "allarkive-rag",
        "choices": [{"index": 0, "delta": {"content": content}, "finish_reason": finish}],
    }
    return f"data: {json.dumps(payload)}\n\n"


def _stream_text(text: str):
    comp_id = f"chatcmpl-{uuid.uuid4().hex[:8]}"
    created = int(time.time())
    chunk = 12
    for i in range(0, len(text), chunk):
        yield _completion_event(comp_id, created, text[i : i + chunk], None)
    yield _completion_event(comp_id, created, "", "stop")
    yield "data: [DONE]\n\n"


def _full_response(content: str) -> dict:
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex[:8]}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": "allarkive-rag",
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": content},
                "finish_reason": "stop",
            }
        ],
        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
    }


# ── FastAPI app ───────────────────────────────────────────────────────────────


app = FastAPI(title="AllArkive RAG Service")


class _Message(BaseModel):
    role: str
    content: str | list[Any] = ""

    def text(self) -> str:
        if isinstance(self.content, str):
            return self.content
        parts = [p.get("text", "") if isinstance(p, dict) else str(p) for p in self.content]
        return " ".join(parts)


class _ChatRequest(BaseModel):
    model: str = "allarkive-rag"
    messages: list[_Message]
    stream: bool = False

    model_config = {"extra": "ignore"}


@app.get("/health")
def health() -> dict:
    return {"status": "ok", "index": Path(_INDEX_PATH).exists()}


@app.get("/status")
def status() -> dict:
    archives = []
    total_bytes = 0
    zim_path = Path(_ZIM_DIR)
    if zim_path.is_dir():
        for f in sorted(zim_path.glob("*.zim")):
            st = f.stat()
            total_bytes += st.st_size
            archives.append(
                {
                    "name": f.name,
                    "size_bytes": st.st_size,
                    "size_gb": round(st.st_size / 1e9, 1),
                    "mtime": st.st_mtime,
                }
            )

    index_meta: dict[str, Any] = {}
    bm25_zims: list[str] = []
    rag_ready = Path(_INDEX_PATH).exists()
    if rag_ready:
        try:
            db = _get_db()
            index_meta = {
                "schema_version": _meta.get("schema_version"),
                "embed_model": _meta.get("embed_model"),
                "embed_dim": int(_meta.get("embed_dim", "0") or 0),
                "quantization": _meta.get("quantization"),
                "chunk_size": int(_meta.get("chunk_size", "0") or 0),
                "extractor_version": _meta.get("extractor_version"),
            }
            bm25_zims = [
                r[0]
                for r in db.execute(
                    "SELECT zim_name FROM indexed_zims WHERE mode='bm25'"
                ).fetchall()
            ]
        except Exception as exc:
            log.warning("status: index meta read failed: %s", exc)

    return {
        "binding": "localhost",
        "kiwix_url": _KIWIX_PUBLIC_URL,
        "webui_url": _WEBUI_PUBLIC_URL,
        "archives": archives,
        "archive_count": len(archives),
        "archive_total_gb": round(total_bytes / 1e9, 1),
        "chat_model": "" if _SEARCH_ONLY else _CHAT_MODEL,
        "embed_model": index_meta.get("embed_model") or _EMBED_MODEL,
        "search_only": _SEARCH_ONLY,
        "rag_ready": rag_ready,
        "index": index_meta,
        "bm25_zims": bm25_zims,
    }


@app.get("/v1/models")
def list_models() -> dict:
    return {
        "object": "list",
        "data": [
            {
                "id": "allarkive-rag",
                "object": "model",
                "created": 0,
                "owned_by": "allarkive",
            }
        ],
    }


@app.post("/v1/chat/completions")
def chat_completions(req: _ChatRequest):
    query = next(
        (m.text() for m in reversed(req.messages) if m.role == "user"),
        None,
    )
    if not query:
        raise HTTPException(status_code=400, detail="no user message")

    try:
        passages = _retrieve(query)
    except RuntimeError as exc:
        answer = str(exc)
    except Exception as exc:
        log.error("retrieval error: %s", exc)
        raise HTTPException(status_code=500, detail="retrieval failed")
    else:
        if not passages:
            answer = NO_SOURCES_TEXT
        elif _SEARCH_ONLY:
            answer = _format_passages_as_citations(passages, _KIWIX_PUBLIC_URL)
        else:
            system = build_system_prompt(passages)
            llm_msgs = [{"role": "system", "content": system}] + [
                {"role": m.role, "content": m.text()}
                for m in req.messages
                if m.role != "system"
            ]
            try:
                raw = _call_ollama(llm_msgs)
            except Exception as exc:
                log.error("ollama error: %s", exc)
                raise HTTPException(status_code=502, detail="ollama error")
            answer = rewrite_citations(raw, passages, _KIWIX_PUBLIC_URL)

    if req.stream:
        return StreamingResponse(_stream_text(answer), media_type="text/event-stream")
    return _full_response(answer)
