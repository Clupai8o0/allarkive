"""Indexing profile presets — RAG_PROFILE=pi|laptop|workstation.

A profile bundles sensible defaults for the knobs that materially affect
indexing speed, storage, and retrieval quality:

  - chunk_size         characters per chunk; larger = fewer rows, often
                       better recall on long-form articles.
  - quantization       int8 (4x smaller) or float32 (baseline).
  - hybrid             skip dense indexing for ZIMs at/above the threshold
                       and rely on libzim's built-in Xapian full-text index
                       at query time.
  - hybrid_threshold_gb threshold ZIMs are evaluated against.
  - batch_size         chunks per Ollama /api/embed request.
  - embed_model        recommended embedding model. nomic-embed-text is the
                       default for laptops/workstations; bge-small-en-v1.5
                       is recommended for Pi (4–6x faster on CPU, vectors
                       are 2x smaller, retrieval within a few MTEB points).

Resolution order (highest priority first):
  1. CLI flag passed to indexer.py
  2. RAG_* env var
  3. Profile preset
  4. Hard-coded fallback (= laptop profile)

Switching profiles between runs implies a full reindex when chunk size,
quantization, or embed model changes — the indexer detects this via the
``meta`` table and refuses to start, pointing the user at ``reindex.sh``.
"""

from typing import TypedDict


class Profile(TypedDict):
    chunk_size: int
    chunk_overlap: int
    quantization: str
    hybrid: bool
    hybrid_threshold_gb: float
    batch_size: int
    embed_model: str


PROFILES: dict[str, Profile] = {
    "pi": {
        "chunk_size": 2000,
        "chunk_overlap": 200,
        "quantization": "int8",
        "hybrid": True,
        "hybrid_threshold_gb": 4.0,
        "batch_size": 16,
        "embed_model": "nomic-embed-text",
    },
    "laptop": {
        "chunk_size": 2000,
        "chunk_overlap": 200,
        "quantization": "int8",
        "hybrid": False,
        "hybrid_threshold_gb": 0.0,
        "batch_size": 64,
        "embed_model": "nomic-embed-text",
    },
    "workstation": {
        "chunk_size": 1500,
        "chunk_overlap": 200,
        "quantization": "float32",
        "hybrid": False,
        "hybrid_threshold_gb": 0.0,
        "batch_size": 128,
        "embed_model": "nomic-embed-text",
    },
}

DEFAULT_PROFILE = "laptop"


def get(name: str | None) -> Profile:
    """Return the named profile, falling back to ``laptop`` for unknown names."""
    if not name:
        return PROFILES[DEFAULT_PROFILE]
    return PROFILES.get(name.strip().lower(), PROFILES[DEFAULT_PROFILE])
