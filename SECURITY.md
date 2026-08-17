# Security Policy

## Supported versions

Security fixes are applied to the latest release line and to `main`.

| Version | Supported |
|---|---|
| `0.1.x` | Yes |
| Earlier versions | No |

## Reporting a vulnerability

Do not open a public issue for a suspected vulnerability.

Use GitHub's [private vulnerability reporting](https://github.com/CorsenAI/hermes-windows-runtime-skills/security/advisories/new).
If that form is unavailable, send the report to `hello@corsen.ai` with the
subject `[SECURITY] hermes-windows-runtime-skills`. Include:

- the affected release, commit, skill, or script;
- the host and execution environment;
- reproduction steps or a minimal proof of concept;
- the expected security impact;
- any suggested mitigation;
- whether the issue is already public or actively exploited.

Remove credentials, tokens, personal data, and unrelated machine details from
logs and attachments. Do not test against systems or data that you do not own
or have explicit permission to assess.

The maintainers aim to acknowledge a complete report within three business
days and provide an initial assessment within seven business days. Resolution
timing depends on severity, reproducibility, and upstream dependencies.

## Disclosure process

Reports are handled under coordinated disclosure. The default disclosure
window is 90 days from acknowledgement, unless the reporter and maintainers
agree on another date. Earlier disclosure may be appropriate after a fix is
available or when active exploitation creates a material public risk.

Credit is offered in the release notes when requested and when disclosure does
not expose sensitive information.

## Scope

This policy covers:

- the two published `SKILL.md` files and their referenced material;
- bundled scripts used by the skills;
- validation, secret-scanning, and packaging logic in this repository;
- release archives produced from this repository.

Vulnerabilities in Hermes Agent itself should also be reported to the upstream
project. Reports about unsafe interactions between this repository and Hermes
are in scope here.
