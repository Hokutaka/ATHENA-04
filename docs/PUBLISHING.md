# Safe publication plan

**Do not switch the current development repository directly from Private to Public.**
Existing commits (including commit authors' email addresses), branches, pull-request refs,
cached views, workflow logs and artifacts can become visible. A later file deletion or
`.gitignore` edit does not erase historical data.

## Separate private development history from public releases

1. Keep the existing repository **Private** as the development archive.
2. Fix public fixtures to use invented names and RFC 5737 documentation IPs.
   Do not include `nodes.tsv`, SSH identities, user environment files, or real screenshots.
3. Review `README.md`, `SECURITY.md`, `docs/`, `cmd/`, `web/`, `windows/`, `tools/`,
   `shell.nix`, `build-checked.sh`, and `.gitignore`.
4. Run `python3 tools/preflight-public.py`, `python3 tools/check-probe.py`,
   `python3 tools/test-probe-structure.py`, `node tools/test-web.mjs`,
   and `bash build-checked.sh`; verify a Linux and Windows probe against controlled targets.
5. Create a **brand-new Private repository** for the public release; copy in only the
   *audited tracked source files*, e.g. with `git archive`, **not** the old `.git/` directory.
   If the exact ATHENA-04 name is desired, rename the old Private repository first,
   and create a new Private ATHENA-04. Do not reuse the old git remote/history.
6. Configure Git author/committer email to the account's GitHub `noreply` address
   and enable email privacy in GitHub Settings > Emails before the first commit.
   Confirm with `git log -1 --format='%an <%ae> | %cn <%ce>'`.
7. Inspect staged paths with `git diff --cached --name-only`; create **one clean initial
   commit**; inspect all files, author metadata, branches, and tags on GitHub.
8. Confirm the [MIT License](../LICENSE) and the copyright attribution use only public identifiers.
   The *Blue Archive* / 小鈎ハレ inspiration is acknowledged as unofficial and does not
   license or include any official game assets.
9. Switch only the *new clean repository* to Public after explicit final approval.

## Environment and runtime data

The CLI intentionally derives its local node database from `HOME` and stores it at
`~/.config/athena-04/nodes.tsv`. This path points to local runtime data; the file
is **not** a source asset and must not be copied into the public export.
`.env`, `.env.*`, `.ssh/`, host identities, logs, and screenshots must also stay out.
Windows PowerShell uses local machine/environment APIs only to obtain runtime telemetry;
actual output can contain identifying hostnames, so do not commit logs or live captures.

**Important:** `tools/preflight-public.py` checks source files for common mistakes.
It is not a full secret scan, privacy audit, or Git history check. Review author/committer
email metadata, all reachable commits and PRs separately.

## Git history caution

If you publish the existing repository and then rewrite or force-push its history,
old commits may remain accessible through commit hashes, refs, PRs, caches, or clones.
GitHub documents these limitations. Use a fresh repository for a clean public start:
https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository

## Security

The current Web UI is **local-only** and has no general authentication. Do not bind it
to the LAN/WAN or expose it through a public reverse proxy.
