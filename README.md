# ATHENA-04 — C4FE / Veritas Observation Network

**Experimental, Linux-hosted multi-OS monitoring console written primarily in Hare.**

ATHENA-04 polls Linux and Windows nodes over SSH and displays read-only host telemetry in a local web console. The control server and CLI are written in Hare; the UI uses HTML/CSS/JavaScript and Windows telemetry uses a fixed PowerShell probe.

> **Status:** v0.6.2-alpha candidate. Successfully exercised with a Linux controller, another Linux VM, and a Windows host in one lab environment. This is not a general security-audited or production-ready remote management service.

## Features

- Linux `/proc`/`uname` telemetry through SSH
- Windows telemetry using a non-administrator PowerShell probe and Win32 APIs; Hare encodes the readable script at runtime
- Hostname, OS/kernel, architecture, logical CPU count, uptime, and memory statistics
- Register, list, select, inspect, remove, and change OS type of monitored nodes
- Browser dashboard with memory usage, last-check indication, and optional polling
- Strict SSH host-key verification and no password storage in ATHENA-04

## Architecture

```text
Firefox (localhost only)
    | GET status / registered nodes / inspect; guarded POST registry changes
    v
Hare Web server (127.0.0.1:8765)
    | fixed argv; no shell from browser
    v
Hare CLI --> ~/.config/athena-04/nodes.tsv  (LOCAL; NOT VERSIONED)
    | OpenSSH, key-based, fixed read-only probes
    +--> Linux SSH server (/proc)
    +--> Windows SSH server (PowerShell / Win32 API)
```

## Requirements

- Linux controller (tested on NixOS), Hare 0.26.x, OpenSSH client, GNU `timeout`, Python 3
- A browser on the **same Linux machine** as the control server
- Target Linux hosts with SSH server and `/proc`, or Windows with OpenSSH Server and PowerShell 5.1
- SSH host keys pre-verified, and noninteractive authentication already configured

## Quick start

```sh
# Run in the cloned repository root, in a Linux environment with prerequisites.
# On NixOS, `nix-shell` can supply Hare, OpenSSH, Python, and coreutils:
nix-shell
bash build-checked.sh
./athena status
./athena node list
./athena-web-v062
```

Open <http://127.0.0.1:8765> from the controller itself. The server stays in the foreground (stop with Ctrl+C). Start it **from the trusted repository root** so the `web/` assets, local `./athena` CLI, and `windows/windows-probe.ps1` can be found. The CLI reads this script and UTF-16LE/Base64-encodes it when checking Windows hosts. Treat the script as executable code; only run ATHENA-04 from a checkout that you trust and control.

To add a host, use `+ ADD` in the web UI, or:

```sh
./athena node add demo-linux HOST_IP SSH_USER linux
./athena node add demo-windows HOST_IP WINDOWS_SSH_USER windows
./athena node check demo-linux
```

Replace `HOST_IP`, `SSH_USER`, and `WINDOWS_SSH_USER` with your **own local configuration**. No real host addresses or credentials are included in this repository. See [Windows setup](docs/WINDOWS-SETUP.md) for a guided, local-network-only example.

## Tests and verification

```sh
python3 tools/check-probe.py
python3 tools/test-probe-structure.py
node --check web/app.js        # if Node.js is available
node tools/test-web.mjs        # optional browser adapter smoke test
bash build-checked.sh
```

The build script checks that generated executables contain the expected v0.6.2 HTTP and Windows probe markers, and that the pre-encoded Base64 blob was removed from the source. It **does not** prove runtime safety or cross-platform compatibility.

## Security and privacy

**Do not expose port 8765 to LAN/WAN or reverse proxy it.** The web console has registry-changing HTTP endpoints and no general authentication or multi-user isolation. SSH probes run under the privileges of the configured remote SSH account. Use a dedicated, minimally privileged Windows account. Do not disable SSH host-key checking.

**Never commit:** `~/.config/athena-04/nodes.tsv`, `.ssh/`, private or public identity files, `authorized_keys`, `known_hosts`, device inventories, personal screenshots, browser captures, credentials, tokens, or logs from real machines. Runtime node information belongs **outside the repository**. See [security notes](SECURITY.md).

Hostnames and IP addresses shown in live web sessions may identify private infrastructure. Review **all screenshots and shell transcripts** before sharing; screenshots are excluded by `.gitignore` by default.

## Current limitations

- Linux-hosted controller only; Windows is a *target*, not the host for Hare.
- Hostnames, OS and basic resource readings only; not CPU load history or remote administrative actions.
- Windows compatibility has been tested only in a limited environment.
- Web server is single-process and experimental; error recovery and request limits need further work.
- The code has not undergone an independent security review.

## License

Original ATHENA-04 source code and documentation are available under the [MIT License](LICENSE). This license covers this project's original materials, **not** third-party game assets, character designs, trademarks, or artwork.

## Name

ATHENA-04 / C4FE is a hobby monitoring console built with the **Hare programming language**. The name and atmosphere are also a playful nod to **Omagari Hare (小鈎ハレ)** from *Blue Archive* and the game's Veritas club. This is an **independent, unofficial fan-inspired project**, not affiliated with, endorsed by, or sponsored by any *Blue Archive* rights holder. No official game artwork, logos, audio, or UI assets are included.
