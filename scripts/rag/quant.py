"""Vector quantization helpers for the RAG pipeline.

sqlite-vec supports ``FLOAT[N]``, ``INT8[N]``, and ``BIT[N]`` storage. This
module exposes a uniform pack/unpack interface and the SQL fragment used to
declare the embedding column for a given quantization mode.

Modes:
  - ``float32``: 4 bytes/dim, baseline. Use for workstations or when index
    size is not a constraint.
  - ``int8``: 1 byte/dim, ~4x smaller, sub-1-point MTEB recall drop on
    cosine-normalised models. Recommended default.
  - ``bit``: 1 bit/dim, ~32x smaller; lossy enough that retrieval should
    re-rank top-K candidates with float32 — not wired up yet, listed for
    schema completeness only.
"""

import math
import struct
from typing import Iterable

SUPPORTED_MODES = ("float32", "int8")
DEFAULT_MODE = "int8"


def vec_column_sql(mode: str, dim: int) -> str:
    """Return the column-type fragment used inside ``vec0(...)``."""
    if mode == "float32":
        return f"FLOAT[{dim}]"
    if mode == "int8":
        return f"INT8[{dim}]"
    raise ValueError(f"unsupported quantization mode: {mode}")


def normalize(v: list[float]) -> list[float]:
    """Unit-normalise a vector. Returns the input if magnitude is zero."""
    mag = math.sqrt(sum(x * x for x in v))
    if mag == 0:
        return v
    return [x / mag for x in v]


def pack(v: Iterable[float], mode: str) -> bytes:
    """Pack a unit-normalised vector to sqlite-vec wire bytes."""
    vlist = list(v)
    if mode == "float32":
        return struct.pack(f"{len(vlist)}f", *vlist)
    if mode == "int8":
        # Map [-1, 1] → [-127, 127]. Inputs already unit-normalised, so all
        # components are bounded; clip defensively for the rare outlier.
        ints = [max(-127, min(127, int(round(x * 127)))) for x in vlist]
        return struct.pack(f"{len(ints)}b", *ints)
    raise ValueError(f"unsupported quantization mode: {mode}")


def degenerate(v: list[float], packed: bytes, mode: str) -> bool:
    """Return True if a vector should be rejected before insert.

    A single bad embedding used to crash the indexer with "could not write
    vector blob"; this preserves the same defensive filter introduced for
    schema v1.
    """
    if not v:
        return True
    if not all(math.isfinite(x) for x in v):
        return True
    if math.fsum(x * x for x in v) <= 0:
        return True
    expected = len(v) * (4 if mode == "float32" else 1)
    if len(packed) != expected:
        return True
    return False
