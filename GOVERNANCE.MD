# GOVERNANCE

How decisions get made in AllArkive. Light-touch by design — this is a v0.x project with two maintainers. We expect this doc to grow as the project does.

## Project structure

AllArkive is an open-source project maintained by **Sam** and **Sham**. We're the founding maintainers and the only people with merge rights for v0.x.

The project has no legal entity, no funding, no commercial relationships. If any of that changes, this document changes first.

## Roles

### Maintainer
- Reviews and merges pull requests.
- Triages issues.
- Has commit access to `main` and `dev`.
- Co-decides on releases and roadmap changes.
- Holds release-signing keys.

Current maintainers: Sam, Sham.

### Contributor
Anyone who has had a contribution merged. No special access; just credit and our gratitude.

### User
Everyone else. Users are welcome in issues, discussions, and PRs without any prior contribution.

## How decisions get made

### Day-to-day
A single maintainer can:
- Merge typo fixes, doc improvements, dependency bumps, and clear bug fixes.
- Triage issues, apply labels, close obvious duplicates.
- Cut a patch release.

### Two-maintainer sign-off required
Both maintainers sign off on:
- Anything that changes a locked decision in `CLAUDE.md`.
- Anything that changes the default security posture.
- Anything that changes what's in a default bundle.
- Adding or removing a maintainer.
- Cutting a minor or major release.
- Changes to license or governance.

### Disagreements between maintainers
If we disagree, we talk it out in the relevant issue or PR. If we still disagree:
1. The status quo wins for now.
2. We open a discussion issue, write down both positions, and either come to consensus within two weeks or escalate to a wider call for input from contributors.

For v0.x there is no formal escalation beyond that. If we ever can't agree on something fundamental, the project can be forked under the AGPL — that is a feature, not a failure.

## Adding maintainers

We expect to add maintainers when:
- A contributor has been consistently active and reliable for at least three months.
- They've shown good judgment in reviews and issues, not just code.
- Both existing maintainers agree.

The path is informal: one of us reaches out, asks if they'd be interested, and if yes, the other maintainer signs off. We add them to the maintainers list, give them merge rights, and update this document.

We don't require contributors to become maintainers — most won't want to, and that's fine.

## Removing maintainers

A maintainer can step down at any time. Open a PR to update this document and the contributor list.

A maintainer can be removed if:
- They've been inactive for six months without notice and don't respond to outreach.
- They've violated the Code of Conduct in a way that warrants removal.
- They've taken actions against the project's interests (publishing keys, leaking pre-disclosure security info, etc.).

For v0.x, removing a maintainer requires the other maintainer's agreement. Once we have more than two maintainers, removal requires majority of the remaining maintainers.

## Releases

See `CHANGELOG.md` for what has been released.

### Versioning
Semantic versioning. `v0.x` is pre-stable; we may make breaking changes between minor versions and will document them.

### Cadence
No fixed cadence. We release when there's something worth releasing. We aim for at least one release every quarter, not less.

### Process
1. Update `CHANGELOG.md`: move `[Unreleased]` content into a new version section.
2. Bump versions in any files that hard-code them.
3. Open a release PR. Both maintainers approve.
4. Merge to `main`.
5. Tag with a signed git tag (`git tag -s v0.x.0`).
6. Cut a GitHub release with checksums and signed artifacts.
7. Verify the Codeberg mirror updated.
8. Announce: project blog/RSS, Mastodon, relevant infosec circles. (HN at our discretion.)

### Release signing
Both maintainers hold release-signing keys. Public keys live in `docs/security/pgp-keys.txt`. Keys are rotated if compromised; rotation is announced via a signed commit.

## Issue and PR triage

We use GitHub labels:
- `bug`, `feature`, `docs`, `chore`, `security`, `roadmap`
- `good-first-issue`
- `help-wanted`
- `out-of-scope` — for things that don't fit v0.1; we discuss whether they fit a later version
- `needs-discussion`
- `blocked` — waiting on upstream or another decision

We aim to:
- Acknowledge new issues within 7 days.
- Respond to PRs within 7 days.
- Close stale issues (no activity for 90 days, no clear path forward) with a note that they can be reopened.

We're a small team. We will sometimes miss these targets. Pinging us politely is fine.

## Security decisions

See `SECURITY.md` for the disclosure process. Security fixes can be merged by a single maintainer if time-sensitive, with the other notified immediately and a follow-up post-mortem in the relevant issue.

## Code of conduct

See `CODE_OF_CONDUCT.md`. Both maintainers are responsible for enforcement. Conduct reports go to `conduct@allarkive.org` *(placeholder)*.

If a report involves a maintainer, the other maintainer handles it. If both maintainers are involved, we will commit to bringing in an independent third party — this is a known weakness of a two-person project and we will fix it as we add maintainers.

## Funding and money

The project takes no money in v0.x. No donations, no sponsorships, no commercial relationships.

If that ever changes:
- This document changes first.
- Funding sources are public.
- No funder gets influence over scope or roadmap beyond what any other contributor would have.
- A legal entity, if needed, is non-profit or fiscal-host based.

## Forking

The project is AGPL-3.0 licensed. Anyone can fork it. We see this as a feature: if we lose interest, get hit by a bus, or take the project somewhere people don't want to follow, the work survives. We will help good-faith forks where we can.

## Changing this document

Changes to `GOVERNANCE.md` require both maintainers to sign off, in a PR with the `governance` label, open for at least 7 days for community comment.