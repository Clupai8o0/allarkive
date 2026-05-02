# SECURITY

How to report security issues in AllArkive.

## Reporting a vulnerability

**Do not** open a public GitHub issue for a security vulnerability.

Email: **security@allarkive.org** *(placeholder — replace before v0.1)*
PGP key: see [`docs/security/pgp-key.txt`](docs/security/pgp-key.txt) *(to be added)*

Please include:
- A description of the vulnerability.
- Steps to reproduce.
- Affected version(s).
- Your assessment of impact.
- Whether you've disclosed this to anyone else.

## What to expect

- **Acknowledgement** within 5 business days.
- **Triage and initial assessment** within 14 days.
- **Coordinated disclosure timeline** agreed with you. Default target is 90 days from acknowledgement to public disclosure.
- **Credit** in the release notes if you want it.

We're a two-person project. We can't promise enterprise SLAs. We will be responsive and honest about what we can and can't do.

## What's in scope

- Code in this repository.
- The default `docker-compose` deployment, with default settings.
- Bundle download and verification scripts.
- The local landing page.
- The RAG pipeline and prompt-injection surfaces.

## What's out of scope

- Vulnerabilities in upstream projects (Kiwix, Ollama, Open WebUI). Report those upstream. We're happy to coordinate.
- Vulnerabilities that require an attacker already on the host machine.
- Vulnerabilities in user-modified deployments (changed bindings, custom reverse proxies, third-party bundles).
- Self-XSS in the local landing page when the user pastes attacker-controlled content into their own browser.
- Issues with services exposed to the public internet against our explicit recommendation. (We document not to do this. If you do it anyway, that's your threat model.)

## Hardening the default posture

Out of the box:
- All services bind to `127.0.0.1`.
- No telemetry.
- Pinned image digests.
- Verified bundle checksums.
- Signed releases and tags.

If you find something that weakens this posture by default, that's in scope.

## Coordinated disclosure preferences

- We prefer coordinated disclosure with a reasonable embargo (default 90 days).
- We will publish a security advisory in GitHub Security Advisories and link from `CHANGELOG.md`.
- We will not pursue legal action against good-faith security research that follows this policy.

## Hall of fame

Once we have one. *(empty for now)*