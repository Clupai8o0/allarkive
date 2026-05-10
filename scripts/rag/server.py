#!/usr/bin/env python3
"""
AllArkive RAG service — OpenAI-compatible API.

Sits between Open WebUI and Ollama. Every query is answered with retrieved
passages from the sqlite-vec index or refused with a no-sources message.

Environment variables:
    OLLAMA_URL          http://ollama:11434
    INDEX_DIR           /index
    KIWIX_PUBLIC_URL    http://127.0.0.1:8081   (used in citation links)
    EMBED_MODEL         nomic-embed-text
    CHAT_MODEL          qwen2.5:7b
    RAG_TOP_K           5
    RAG_MAX_DISTANCE    1.0  (L2 distance on normalised vectors; lower = more similar)
"""

import json
import logging
import math
import os
import sqlite3
import struct
import time
import uuid
from pathlib import Path
from typing import Any

import httpx
import sqlite_vec
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from citations import rewrite_citations
from prompt import NO_SOURCES_TEXT, build_system_prompt

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger("rag.server")

_OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama:11434")
_INDEX_DIR = os.environ.get("INDEX_DIR", "/index")
_KIWIX_PUBLIC_URL = os.environ.get("KIWIX_PUBLIC_URL", "http://127.0.0.1:8081")
_EMBED_MODEL = os.environ.get("EMBED_MODEL", "nomic-embed-text")
_CHAT_MODEL = os.environ.get("CHAT_MODEL", "qwen2.5:7b")
_TOP_K = int(os.environ.get("RAG_TOP_K", "5"))
_MAX_DIST = float(os.environ.get("RAG_MAX_DISTANCE", "1.0"))
_INDEX_PATH = str(Path(_INDEX_DIR) / "index.db")

_ZIM_DIR = os.environ.get("ZIM_DIR", "/data")

_db: sqlite3.Connection | None = None


def _get_db() -> sqlite3.Connection:
    global _db
    if _db is None:
        if not Path(_INDEX_PATH).exists():
            raise RuntimeError(
                f"Vector index not found at {_INDEX_PATH}. "
                "Run: docker compose exec rag python indexer.py"
            )
        _db = sqlite3.connect(_INDEX_PATH, check_same_thread=False)
        _db.enable_load_extension(True)
        sqlite_vec.load(_db)
        _db.enable_load_extension(False)
    return _db


def _pack(v: list[float]) -> bytes:
    return struct.pack(f"{len(v)}f", *v)


def _normalize(v: list[float]) -> list[float]:
    mag = math.sqrt(sum(x * x for x in v))
    return [x / mag for x in v] if mag else v


def _embed(text: str) -> list[float]:
    with httpx.Client() as client:
        r = client.post(
            f"{_OLLAMA_URL}/api/embeddings",
            json={"model": _EMBED_MODEL, "prompt": text},
            timeout=30.0,
        )
        r.raise_for_status()
    return _normalize(r.json()["embedding"])


def _retrieve(query: str) -> list[dict]:
    emb_bytes = _pack(_embed(query))
    db = _get_db()
    rows = db.execute(
        """
        WITH knn AS (
            SELECT chunk_id, distance
            FROM   chunk_embeddings
            WHERE  embedding MATCH ?
            AND    k = ?
        )
        SELECT c.zim_name, c.article_path, c.title, c.text, knn.distance
        FROM   knn
        JOIN   chunks c ON c.id = knn.chunk_id
        ORDER  BY knn.distance
        """,
        [emb_bytes, _TOP_K],
    ).fetchall()
    return [
        {
            "zim_name": r[0],
            "article_path": r[1],
            "title": r[2] or r[1].rsplit("/", 1)[-1],
            "text": r[3],
            "distance": r[4],
        }
        for r in rows
        if r[4] <= _MAX_DIST
    ]


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
    return {
        "binding": "localhost",
        "kiwix_url": _KIWIX_PUBLIC_URL,
        "archives": archives,
        "archive_count": len(archives),
        "archive_total_gb": round(total_bytes / 1e9, 1),
        "chat_model": _CHAT_MODEL,
        "embed_model": _EMBED_MODEL,
        "rag_ready": Path(_INDEX_PATH).exists(),
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
