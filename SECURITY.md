# Security policy and publication notes

ATHENA-04 v0.6.2 is an experimental, local-only prototype, **not** a hardened production monitoring service.

- The Web UI has mutation endpoints but **no full authentication**. Never expose `127.0.0.1:8765` through reverse proxy, router forwarding, SSH port forwarding, or a public IP.
- SSH is read-only by program design; actual permissions are determined by the remote account. Use dedicated non-admin Windows and least-privilege Linux accounts.
- Use known and verified SSH host keys. Do not use `StrictHostKeyChecking=no` as a workaround.
- The registry `~/.config/athena-04/nodes.tsv` contains private infrastructure information. It must not be included in public sources or tickets.
- Web captures and screenshots show hostnames, IP addresses, usernames and live resources. Sanitize before posting.
- Windows PowerShell scripts use standard OS APIs. Read-only telemetry does not guarantee that the whole Web server is secure.
- Error handling, concurrency controls and resilience to malformed/disconnected HTTP clients need further work before exposing the service beyond the local lab.

To report a vulnerability, contact the maintainer privately rather than putting exploits, infrastructure addresses or credentials into a public issue.

## Checklist before any public release

1. Verify `git status` / `git ls-files` includes only reviewed source and documents.
2. Search all staged text for personal user names, IPs, machine names, SSH fingerprints, tokens and home-directory paths.
3. Never add environment-specific files or screenshots by `git add -f` without review.
4. Review **the entire Git history**, not just the latest tree, before changing a private repository to public.
5. Decide a LICENSE, test a fresh clone on a disposable machine, and keep the Web service loopback-only.
