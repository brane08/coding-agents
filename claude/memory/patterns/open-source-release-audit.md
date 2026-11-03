# Open-source release audit checklist

Covers: what to scan and decide before making a private repo public (licence, secrets, personal data, provenance, history). Checklist only; record findings in the repo, never the values (no secrets, emails, hostnames, licence text).

## Decide first
- Licence model (permissive, copyleft, dual with commercial). Dual licensing needs sole copyright: CLA or assignment for outside contributions, confirm ownership of AI-assisted code and of any earlier-language/earlier-package code, and consent for third-party `@author` tags.
- Copyleft network clause (AGPL section 13): UI/SPA must link to source.
- History: keep, rewrite (`git filter-repo`: mailmap + message callback, changes all hashes and breaks open PRs), or publish a fresh single-commit repo. Decide before anything else is edited.
- What ships: AI plans/specs, `.claude/`/agent memory, `CLAUDE.md`, tracking files (sanitise or exclude; tracked files need `git rm -r --cached` even when ignored).

## Scan (read-only first)
- Secrets in tree and in history: private keys/PEMs, tokens, `.env`, keystores, password assignments, deleted CI workflows and seed SQL. Run a dedicated scanner (gitleaks/trufflehog) over full history; grep alone is not enough.
- Dev keys that fall back under any non-prod profile and ship in every jar/image: treat as compromised, remove, generate at startup or read from env, rotate.
- Default admin/system credentials and hashes in seeds, loaders, test data and docs; check whether they match a public sample; enforce password change server-side.
- Stray refs that publish with the repo: stash refs, tool checkpoint refs, extra branches/tags.
- Personal data: commit author identities (personal mailbox, machine hostname), commit-message trailers/URLs from tools, home paths/OS usernames/handles in docs and memory, real-looking seed domains (switch to reserved example domains), dumps and zips (sample every table), EXIF on images, bytecode (`.pyc`) in archives.
- Deployer defaults: unauthenticated management endpoints, superuser DB account, dev identity-provider realms in main resources, localhost IdP in the prod bundle, per-pod rate limits behind a proxy, outbound PII to third-party AI APIs, stale Dockerfiles.

## Licences and provenance
- Add: full licence text with holder, commercial-licence note (states open use needs no permission), `NOTICE`/third-party list, `<licenses>` in poms, `license` in `package.json`, README section, contributor guide (authorship, grant of rights).
- Verify dependency licences from real metadata (licence plugin for Maven, `license-checker` for npm), not memory. Flag weak copyleft/dual: pick the compatible option explicitly (e.g. elect the compatible alternative of a dual licence), keep attribution for LGPL runtime libs, note fat/shaded jars bundle driver notices.
- Unverified-by-default list: transaction managers, migration tools, build-time recipe plugins (may be source-available), browser binaries.
- Assets: every image/font/icon needs a known owner or licence; framework-default favicons and starter templates should be replaced or removed; runtime-loaded fonts are a privacy note.
- Seed/test domains and `@author` tags: caller-check before bulk replace.

## Order
1. Licence and ownership. 2. Provenance of assets. 3. Docs/memory exposure. 4. History decision. 5. Remove keys, fix defaults, rotate. 6. Edit licence files, poms, README, third-party notices, seed domains. 7. Verify licences online. 8. Secret scan over full history. 9. Push only the new default branch.

## Not checked by default
Image EXIF, seed addresses/postcodes, mail config blocks, CI config, whether seed domains resolve, full-history scan.
