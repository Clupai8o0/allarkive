# CONTRIBUTING

Thanks for thinking about contributing. AllArkive is a small project — two maintainers and the people we can convince to help. Pull requests, issues, bundle proposals, install-guide rewrites, translations, and "I tried this and it didn't work" reports are all welcome.

## Before you start

1. Read [`README.md`](README.md), [`ARCHITECTURE.md`](docs/ARCHITECTURE.md), and [`ROADMAP.md`](ROADMAP.md). The project has firm scope boundaries for v0.1.
2. Check [`TODO.md`](TODO.md) for current work and open issues for what others are doing.
3. Read [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md). It applies to every interaction in issues, PRs, and discussions.

## Ways to contribute

You don't need to write code.

### Code
- Bug fixes
- Improvements to the install guides
- RAG pipeline improvements
- Better default model selection logic
- Cross-platform install guides we don't yet have

### Content / curation
- Bundle proposals — a focused archive for a topic, language, or region
- Bundle audits — verify what's actually in a default bundle, flag licensing issues
- Translations of the README and landing page

### Documentation
- Walkthroughs and tutorials
- Better screenshots
- Fixing things that confused you when you tried to install

### Reporting
- "I tried to install this and X went wrong" is a valid contribution
- Reproduction steps and your OS / hardware help a lot

## How to propose a change

### For small things (typos, doc fixes, obvious bugs)
Open a PR directly. We'll review.

### For anything else
Open an issue first. Describe the problem, not the solution. We'll discuss whether and how before you sink time into a PR.

### For new bundles
Use the **Bundle Proposal** issue template. Include:
- What's in the bundle
- Why it's useful and to whom
- Total size
- Source URLs and SHA-256 checksums for each ZIM
- License of each item
- Whether you're offering to maintain it

Bundles that aren't compatible with our default-license posture (no proprietary content, no incompatible licenses) won't be merged into the defaults but can live as user-curated.

## Development setup

```bash
git clone https://github.com/allarkive/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
./scripts/bootstrap.sh
```

Linters and checks:
```bash
# Markdown
npx markdownlint-cli2 "**/*.md"
# Shell
shellcheck scripts/**/*.sh
# Compose
docker compose -f compose/docker-compose.yml config
# Python (RAG)
ruff check scripts/rag/
ruff format --check scripts/rag/
```

CI runs all of the above.

## Branch and commit conventions

- Branch from `dev`, not `main`.
- Branch names: `feat/<short-name>`, `fix/<short-name>`, `docs/<short-name>`.
- Commits: [Conventional Commits](https://www.conventionalcommits.org/), imperative mood, present tense.

```
feat(rag): add citation-aware retrieval over ZIM index
fix(compose): bind ollama to 127.0.0.1 by default
docs(install): add Pi text-only walkthrough
```

## Sign-off (DCO)

Every commit must include a `Signed-off-by` line. We use the [Developer Certificate of Origin](https://developercertificate.org/) instead of a CLA.

```bash
git commit -s -m "feat(rag): your message"
```

This adds: `Signed-off-by: Your Name <your.email@example.com>` and asserts you have the right to submit the contribution under the project's license.

## Pull request checklist

Your PR is ready for review when:

- [ ] Branch is rebased on the latest `dev`.
- [ ] All commits are signed off (DCO).
- [ ] CI is green (lint, shellcheck, compose validation, RAG tests if applicable).
- [ ] Docs updated in the same PR for any user-visible change.
- [ ] `CHANGELOG.md` updated under `[Unreleased]`.
- [ ] No secrets, personal data, or floating image tags in the diff.
- [ ] You've tested locally (note your OS and what you ran in the PR description).

## Review process

- A maintainer (Sam or Sham, for v0.x) reviews your PR.
- We aim for a first response within a week. Often faster, sometimes slower.
- We may ask for changes. We may close PRs that drift outside scope, with a reason.
- Once approved, we squash-merge to `dev`. Releases promote `dev` to `main`.

## Scope discipline

If your change adds a feature outside [`ROADMAP.md`](ROADMAP.md) v0.1 scope, we will ask you to either:

1. Close the PR and open an issue with a `roadmap` label proposing it for v0.2+, or
2. Trim the PR to the in-scope subset.

This isn't because we don't like the idea. It's because scope creep is the most common way small open-source projects die.

## What we won't accept

- Telemetry of any kind.
- Default-on remote access.
- Floating image tags.
- Bundled content with an unclear or incompatible license.
- Code that depends on a third-party cloud service at runtime.
- Anything that erases the disclaimers on the chat surface.
- Hostility, condescension, or harassment in PRs or issues — see [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Maintainers

Current maintainers:
- Sam *(GitHub handle TBD)*
- Sham *(GitHub handle TBD)*

We expect to add more maintainers as the project grows. See [`GOVERNANCE.md`](GOVERNANCE.md).

## Licensing

By contributing, you agree that your contributions will be licensed under the same license as the rest of the project (AGPL-3.0 for glue code, or the original license for any third-party content you bundle).

### Why AGPL-3.0

We chose AGPL-3.0 over MIT or Apache-2.0 because AllArkive is infrastructure: if someone forks the glue code, improves it, and runs it as a service, those improvements should come back to the project. The Affero clause closes the "SaaS loophole" that standard GPL leaves open. MIT would have been simpler to adopt, but the project's value is in the network effect of a shared, auditable codebase—not in maximum corporate adoption—so the copyleft cost is worth paying. Bundled content (ZIM archives, model weights) keeps its own license; AGPL-3.0 covers only the glue code in this repository. This decision was made jointly by Sam and Sham and recorded in `CLAUDE.md` as a locked decision; relitigate it by opening an issue, not a PR.