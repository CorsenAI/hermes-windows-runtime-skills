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

Maintainers will acknowledge a complete report as soon as practical, validate
its impact, and keep the reporter informed when there is material progress.
Response and remediation times depend on severity, reproducibility, maintainer
availability, and upstream dependencies; no service level is guaranteed.

## Disclosure process

Reports are handled under coordinated disclosure. Reporter and maintainers
should agree on disclosure timing after impact and remediation options are
understood. Maintainers may credit reporters who request attribution when that
does not expose sensitive information.

## Scope

This policy covers:

- the two published `SKILL.md` files and their referenced material;
- bundled scripts used by the skills;
- validation, secret-scanning, and packaging logic in this repository;
- release archives produced from this repository.

Vulnerabilities in Hermes Agent itself should also be reported to the upstream
project. Reports about unsafe interactions between this repository and Hermes
are in scope here.
