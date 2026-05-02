# THREAT_MODEL.md

What AllArkive does and does not protect against. This page exists because every claim a project makes about resilience needs to be checkable.

If you're trying to figure out whether to trust AllArkive for a specific use, read this end to end.

## What this project is

AllArkive is:
- A local copy of curated open knowledge archives.
- A local AI that searches and summarises that knowledge.
- A glue layer that makes the above installable in one command.

AllArkive is **not**:
- A medical tool, legal tool, or survival tool.
- A secure messenger, anonymous network, or surveillance-resistant comms layer.
- A replacement for the open internet.
- A replacement for a doctor, lawyer, electrician, or any other professional.
- A guaranteed-correct source of information.

## Disclaimers

> **The AI can be wrong.** RAG with citations makes its output checkable, not infallible. Read the citations.

> **Not professional advice.** AllArkive is a research and reference tool. It is not a substitute for professional medical, legal, or safety advice. If a question matters, talk to a qualified human.

> **Bundled content can be wrong, outdated, biased, or offensive.** Wikipedia and Project Gutenberg contain material that is unpleasant, incorrect, or stale. They are also part of the historical record. We don't filter by default. You can choose what to bundle.

## Threats we protect against (partly)

### Loss of internet access for a single user
**Protects against**: ISP outage, household connectivity loss, travelling without reliable internet, working in a remote location.
**How**: every layer functions offline once installed. The archive doesn't need the internet. The model doesn't call out. The RAG pipeline runs on localhost.
**Caveats**: the archive is a snapshot. The longer your install runs without an update, the staler your copy becomes.

### Cloud-service rug-pulls
**Protects against**: a SaaS shutting down, changing pricing, removing features, or losing your data.
**How**: nothing depends on a third-party cloud at runtime. Your archive, your model, your data, your machine.
**Caveats**: upstream open-source projects (Kiwix, Ollama, Open WebUI) could shift. Our pinning and the AGPL license make forks viable, but a fork is still work.

### Censorship of specific sources
**Protects against**: country-level or ISP-level blocks on Wikipedia, Stack Exchange, etc.
**How**: once the ZIM is on your disk, no one can block your access to it.
**Caveats**: you have to acquire the ZIM in the first place, which requires either an unblocked connection at install time or a sneakernet copy from someone who has one. We don't currently document sneakernet workflows; that's a v0.2 candidate.

### Surveillance by third parties of your queries
**Protects against**: search engines, LLM providers, or analytics platforms logging what you read and ask.
**How**: nothing leaves your machine. No telemetry. Default network binding is `127.0.0.1`.
**Caveats**: if you opt in to LAN or remote access, your network operator can see traffic to the host. If your machine is compromised, all bets are off.

### Local-machine privacy
**Protects against**: queries and chat history living on someone else's server.
**How**: chat history is local (Open WebUI's sqlite, on your disk). You can wipe it.
**Caveats**: it's a regular sqlite file. If your disk is unencrypted, anyone with physical access to the machine can read it. Use full-disk encryption.

## Threats we do NOT protect against

### A targeted attacker with code execution on your machine
If someone has a shell on your box, AllArkive can't help you. Our threat model assumes the host is trusted. Use OS-level hardening, full-disk encryption, and reasonable update hygiene.

### Hallucinations and confidently wrong answers
We mitigate this with required citations and a "no sources found" path. We do not eliminate it. Open-weight models still hallucinate. The user must check the citations. We say so loudly in the UI; we cannot enforce it.

### Poisoned content in custom bundles
If you add a third-party ZIM that contains hidden adversarial content (prompt-injection text, deliberately wrong information), your local AI may be manipulated. The default bundle pulls from sources we trust at the project level. Custom bundles are your responsibility. See the "Supply chain" section below.

### Supply-chain attacks on the bundle pipeline
If an upstream ZIM mirror is compromised between us pinning a checksum and you downloading, our checksum verification will fail. **If you bypass checksum verification, you accept the risk.**

### Trusting the project itself
Running our installer means running our code with your user permissions. Mitigations:
- Open source and AGPL-3.0 licensed. You can read every line.
- Signed releases and signed git tags.
- Aspiration: reproducible builds.
- Independent install on a second machine by a second person is part of our release process.

If you don't trust us, don't install. Or read the source first. Or wait for someone else to verify the release.

### Your ISP or network operator seeing that you're using AllArkive
The project doesn't add any obfuscation. Local-only deployments don't generate any external traffic at runtime, but installation and updates do (image pulls, ZIM downloads, model downloads). Use a VPN if your network operator caring about that is a concern.

### Physical seizure of your hardware
If your machine is taken and decrypted, everything you've stored is readable. We don't ship anti-forensic features. Use disk encryption. Have a plan.

### Legal exposure for the content in your archive
Some content in the bundles we ship may be illegal in some jurisdictions. We curate from sources with established legal standing in most places (Wikipedia, Project Gutenberg, etc.) but we are not lawyers and this is not legal advice. **You are responsible for what you possess and serve from your machine.**

## Build learnings (updated during v0.1 development)

Things we learned while building that informed or changed our understanding of the threat surface:

### Open WebUI ships with authentication disabled by default
The default config (`WEBUI_AUTH=false`) means no login is required to use the chat interface. This is the right default for a single-user localhost install — adding a login screen adds friction with no security benefit when the host is already trusted. **If you enable LAN access, enable authentication before exposing the port.** See `docs/deployment/lan-access.md`.

### The RAG "no sources found" path is enforced at the API level
The RAG service returns a structured error response when retrieval finds nothing relevant, rather than passing a bare query to the model. The model is not asked to answer without sources. This is a defence against the model hallucinating plausible-sounding citations, but it does not protect against the model generating wrong answers when it does have sources — the sources only prove the passage existed, not that it is correct.

### Inter-service communication goes over a Docker bridge network
Kiwix, Ollama, Open WebUI, and the RAG service communicate over a Docker-managed bridge network. From outside Docker, only the published ports (`127.0.0.1:PORT`) are reachable. Ollama's API is published to the host for debugging convenience but would ideally remain internal-only in a future hardened build.

### The RAG API key is not a security boundary
`RAG_API_KEY` in `compose/.env` (default: `allarkive`) is used to satisfy Open WebUI's requirement for an API key when configuring an external OpenAI-compatible endpoint. It is not a meaningful secret — anyone who can reach `127.0.0.1:8000` can call the RAG API regardless. Don't treat it as authentication.

### Image tags are not yet pinned to digests
The compose files pin image versions (e.g. `kiwix:3.8.2`) but not digests. Digest pinning is documented in the compose file as a required step before production use. Until digests are pinned, a compromised or replaced upstream image with the same tag could be pulled silently on `docker compose pull`. Pin digests before any deployment that matters.

### iFixit content is CC-BY-NC-SA — not for commercial use
The default `minimal` and `balanced` bundles include iFixit repair guides, which are licensed CC-BY-NC-SA 3.0. Non-commercial use is permitted; commercial deployment is not. This is a legal exposure, not a security one, but it is worth knowing before deploying in a commercial context.

## Default security posture

Out of the box:
- All services bind to `127.0.0.1` only.
- No service is exposed to the LAN or the internet.
- No telemetry, no analytics, no external CDN.
- No login screen on the local landing page (it's localhost — anyone with shell access already has more power than the login screen).
- Open WebUI has no login screen by default (`WEBUI_AUTH=false`) — same reasoning as above; enable it if you expose the port to the LAN.
- No outbound network calls at runtime once installed.

If you change any of these, you're choosing a different posture. Document your reasoning to your future self.

## Reporting a vulnerability

See `SECURITY.md`.

## Reviewing this document

We update `THREAT_MODEL.md` when:
- We learn something during a build that changes our understanding of a threat.
- A user reports a scenario we hadn't considered.
- A new release changes the default posture.

If something in this doc feels wrong or incomplete, open an issue with the `threat-model` label.