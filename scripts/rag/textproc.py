"""Shared text extraction and chunking for the RAG pipeline.

Both the indexer and the server must produce identical extracted text from a
given ZIM article, otherwise the char_offset / char_len stored in the index
would point at the wrong bytes. The version constant below is written into
``meta.extractor_version`` at index time and verified at query time; bumping
the value forces a reindex.
"""

import re

# Bump when _html_to_text or chunk_offsets changes in a way that shifts byte
# offsets within the extracted article text. The server verifies this at
# startup against the value stored in ``meta.extractor_version`` and refuses
# to run on a mismatch.
EXTRACTOR_VERSION = 2

_STRIP_CLASS_PREFIXES = re.compile(
    r"^(toc|sidebar|navbox|reflist|mw-references|catlinks)", re.I
)

_BS_PARSER = "lxml"


def html_to_text(html: str) -> str:
    """Strip chrome from a ZIM HTML page and return the article body as text.

    Uses lxml — 5–10x faster than html.parser on Wikipedia-scale articles.
    The class regex matches individual class names (anchored with ^), not the
    joined class attribute, so Vector-skin classes like
    ``vector-toc-not-available`` no longer decompose the whole document.
    """
    from bs4 import BeautifulSoup  # local import keeps the module light

    soup = BeautifulSoup(html, _BS_PARSER)
    for tag in soup.find_all(["nav", "aside", "footer", "script", "style"]):
        tag.decompose()
    for tag in soup.find_all(
        lambda t: any(
            _STRIP_CLASS_PREFIXES.match(c) for c in (t.get("class") or [])
        )
    ):
        tag.decompose()
    return soup.get_text(separator="\n", strip=True)


def chunk_offsets(text_len: int, size: int, overlap: int) -> list[tuple[int, int]]:
    """Return (start, end) pairs that cover [0, text_len) with overlap.

    Pairs are unstripped — slicing ``text[start:end]`` reproduces what the
    indexer saw before applying ``.strip()``. The server re-strips on read
    so trailing-whitespace differences never shift offsets.
    """
    if text_len <= 0 or size <= 0:
        return []
    if overlap < 0 or overlap >= size:
        overlap = max(0, size // 8)
    step = size - overlap
    spans: list[tuple[int, int]] = []
    start = 0
    while start < text_len:
        end = min(start + size, text_len)
        spans.append((start, end))
        if end >= text_len:
            break
        start += step
    return spans


def slice_chunk(text: str, char_offset: int, char_len: int) -> str:
    """Recover a chunk from the article text using the stored span.

    The indexer skipped pieces shorter than 50 chars; the same predicate
    holds here for symmetry, but it's the caller's job to apply if needed.
    """
    end = char_offset + char_len
    return text[char_offset:end].strip()


def title_prefixed(title: str | None, piece: str) -> str:
    """Prepend the article title to a chunk for embedding only.

    Free retrieval improvement: vectors are slightly more discriminative
    when the article context is in the embedded text. The title is not
    stored as part of the chunk — it's only seen by the embedding model.
    """
    if title:
        return f"{title}\n\n{piece}"
    return piece
