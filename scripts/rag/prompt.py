"""Prompt templates and citation enforcement for the RAG pipeline."""

_SYSTEM_TEMPLATE = """\
You are AllArkive's research assistant. You answer questions exclusively using the passages provided below.

Rules:
1. Cite every claim with [N] notation corresponding to the passage number.
2. Use only information from the passages. Do not add knowledge from outside them.
3. If no passage is relevant to the question, respond with exactly:
   no sources found for this question.
4. Do not invent citations. If you cannot support a statement, omit it.

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
