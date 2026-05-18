# Custom bundle — license tracking

This directory holds **user-supplied** archive listings. The named bundles
(`minimal`, `balanced`, `comprehensive`) ship with vetted licensing in their
own `LICENSE.md`. Custom bundles do not — *you* are responsible for tracking
the license of every archive you add to `manifest.json`.

When you add a ZIM with `scripts/fetch-bundle.sh custom --add <spec>`, the
manifest entry is seeded with a placeholder license. Replace it with the
actual upstream license before you redistribute the bundle.

## Template

For each ZIM in `manifest.json`, record:

```
## <filename>.zim
- Source URL: <url>
- Upstream license: <SPDX identifier or full name>
- License URL: <link>
- Attribution required: yes / no
- Redistribution allowed: yes / no / with notice
- Notes: <anything else>
```

## Why this matters

The glue code in this repository is AGPL-3.0. The *content* of each ZIM
keeps its own license — Wikipedia is CC-BY-SA, Project Gutenberg is mostly
public domain, iFixit is CC-BY-NC-SA (non-commercial only), and so on.
Bundling unlicensed or proprietary content into an AllArkive install is
your liability, not the project's. See `THREAT_MODEL.md` for context.
