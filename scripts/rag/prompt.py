"""Prompt templates and citation enforcement for the RAG pipeline."""

_SYSTEM_TEMPLATE = """\
You are AllArkive's research assistant. You answer using the passages provided below.

Rules:
1. Cite every factual claim with [N] notation corresponding to the passage number.
2. Use only information from the passages. Do not add facts from outside them.
3. If a passage discusses the topic the user asked about — even tangentially or
   in a related context — synthesise what it says and cite it. Partial answers
   are useful; say what the passages do cover and what they don't.
4. Only respond with exactly "no sources found for this question." when the
   passages have no connection to the user's topic at all. A passage that
   merely mentions a related concept still counts as relevant.
5. Do not invent citations. If you cannot support a statement with a passage,
   omit the statement.

Passages:
{passages}
"""

NO_SOURCES_TEXT = (
    "No relevant sources were found in the local archive for this question. "
    "The local knowledge base may not cover this topic. "
    "Try rephrasing, or check which bundle is installed with scripts/fetch-bundle.sh."
)


def build_system_prompt(passages: list[dict]) -> str:
    passage_blocks = "\n\n".join(
        f"[{i + 1}] {p['title']} ({p['zim_name']})\n{p['text']}"
        for i, p in enumerate(passages)
    )
    return _SYSTEM_TEMPLATE.format(passages=passage_blocks)
