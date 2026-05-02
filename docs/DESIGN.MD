# DESIGN.md

How AllArkive looks, sounds, and behaves. Applies to the landing page, the README, the docs site, error messages, and anything else a user reads.

## Tone

**Dry, practical, resilience-framed. Not apocalypse-coded.**

The project sits on a real problem — centralisation, surveillance, censorship, AI slop in search results. We name those problems plainly. We don't dramatise them, and we don't tip into prepper or doomsday energy.

### Yes
- "An offline research assistant that runs on your own hardware."
- "Useful when your internet is fine. More useful when it isn't."
- "Censorship resistance, privacy, and educational access."
- "RAG with citations is checkable, not infallible."

### No
- "Survive the collapse of the internet."
- "Your most valuable asset after food and water." *(yes, this is in the planning notes — it doesn't ship)*
- "When the grid goes down…"
- Bunker, prepper, doomsday, apocalypse, end times, SHTF, last line of defence.
- "Civilization-in-a-box" as a public tagline. (Internal shorthand only. The public framing is library + research assistant.)

### Voice rules
- Plain words over jargon. "Local AI" not "edge inference."
- Short sentences. Long sentences for emphasis only.
- Em dashes without spaces: `word—word`.
- No exclamation marks. No emoji in the README, landing page, or any error message.
- "We" is correct (Sam and Sham co-built this). Don't write copy that reads as a single founder.
- Never claim more than RAG can deliver. The model can be wrong. Say so.

## What we never market this as

- Medical advice
- Legal advice
- Survival or emergency-preparedness advice
- A replacement for the internet
- A replacement for a doctor, lawyer, or expert

If a user wants to use it for those things, that's their call. We don't pitch it that way.

## Landing page direction

The landing page (`landing/`) is the local entry point at `http://localhost:8080`. It is **not** marketing — it is a working tool the user sees every time they open the project.

### Layout (single page, three sections)

1. **Header**
   - Project name and version
   - Three buttons: **Search the archive**, **Chat with the AI**, **Manage what's installed**
   - One-line status: "Archive: 4 sources / 47 GB. Model: qwen2.5:7b. RAG: ready."

2. **Search and chat**
   - Single search box with a toggle: `Search archive` | `Ask AI`
   - "Ask AI" responses always show numbered citations linking back to the archive viewer
   - A persistent disclaimer line under the chat: *"Responses can be wrong. Check the citations."*

3. **Manage**
   - List of installed bundles with size, last updated, and a "verify checksums" button
   - "Add bundle" → links to docs
   - "Remove bundle" with confirmation

### Visual direction

- **Minimal.** White or near-white background, dark text, one accent colour. No hero images, no stock photography, no illustrations of bunkers or globes.
- **Information-dense in a calm way.** Like a library catalogue, not like a SaaS landing page.
- **Monospace for technical bits.** Sans-serif for body. Both system fonts — no web fonts, no external assets.
- **Static HTML + a tiny bit of vanilla JS.** No build step. No framework. Anyone should be able to read the source and understand what it does.
- **Dark mode** via `prefers-color-scheme`. Same restraint.

### What the landing page must not do

- No telemetry of any kind.
- No external CDN. Every asset bundled and served from `localhost:8080`.
- No analytics. No "rate this response." (User feedback is welcome via GitHub issues.)
- No login screen by default — it's `localhost`.

## UX principles

1. **Sources before output.** When the AI answers, citations render with the answer, not after a delay. If retrieval found nothing, say "no sources found" rather than letting the model guess.
2. **One way to do each thing.** v0.1 is not the place for power-user toggles. The advanced surface lives in config files for now.
3. **Failure messages are honest.** "Ollama is not running" not "Something went wrong."
4. **Default-local is visible.** The status line shows "binding: localhost only" so the user knows nothing is exposed.
5. **The user owns their data.** No "cloud sync," no "share to community." Export to plain files; that's it for v0.1.

## Naming

- **Project**: AllArkive (one word, two capitals: A and A).
- **Components** in code and docs:
  - `archive` — the Kiwix layer
  - `ai` — the Ollama + Open WebUI layer
  - `rag` — the retrieval pipeline
  - `landing` — the local landing page
  - `bundles` — curated sets of ZIMs (`minimal`, `balanced`, `comprehensive`)
- **Don't** invent cute internal names for components. Boring names age better.

## Disclaimers — required text

These appear verbatim in the locations listed.

### In the chat UI, persistent under the input
> Responses can be wrong. Check the citations.

### On the landing page footer
> AllArkive is a research and reference tool. It is not a substitute for professional medical, legal, or safety advice.

### In the README, in the "What's in the default bundle" section
> The AI can be wrong. RAG with citations makes its output checkable, not infallible. Not a substitute for professional medical, legal, or safety advice.

### On `THREAT_MODEL.md`
The full honesty page. See that doc.

## Copy patterns

### Buttons
Verb-first, two words max where possible.
- "Install bundle" not "Click here to install a bundle"
- "Verify checksums" not "Run checksum verification"
- "Open archive" not "Launch the archive viewer"

### Headings in docs
Sentence case. No title case.
- ✅ "How retrieval works"
- ❌ "How Retrieval Works"

### Links
Inline, descriptive. Never "click here."
- ✅ "See the [install guide](docs/install/)."
- ❌ "Click [here](docs/install/) for the install guide."

## What this section is not

This is a tone-and-UX style guide, not a brand book. We don't have logos, illustrations, or marketing collateral, and v0.1 doesn't need them. If we add them later, they go in `docs/brand.md` and follow the same restraint as everything else.