# Windows target setup (SSH + PowerShell)

Use this only in a trusted **private lab network**. Substitute your own private addresses; nothing here assumes a particular user, hostname or VirtualBox installation.

## 1. Get your own IP addresses

On the **Windows** target (Administrator PowerShell):

```powershell
Get-NetIPAddress -AddressFamily IPv4
whoami
```

Determine the address of the dedicated host-only or otherwise isolated interface. For the rest of this guide, we use variables instead of any real lab details:

```powershell
$TargetIP = Read-Host 'Windows private-interface IPv4 address'
$AllowedSubnet = Read-Host 'Trusted controller subnet in CIDR notation'
```

The SSH server should not be exposed to the internet or unrestricted LANs.

## 2. Install and start Windows OpenSSH Server

```powershell
Get-WindowsCapability -Online -Name 'OpenSSH.Server*'
# Only when State is NotPresent:
# Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
```

Review existing firewall rules before changing them. If the default `OpenSSH-Server-In-TCP` rule permits excessive access and you do not need it for other uses, disable it in an **Administrator PowerShell** and create a scoped allow rule:

```powershell
Get-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -ErrorAction SilentlyContinue | Disable-NetFirewallRule
New-NetFirewallRule -Name 'ATHENA04-Private-SSH' `
  -DisplayName 'ATHENA-04 isolated SSH' -Direction Inbound -Action Allow `
  -Protocol TCP -LocalPort 22 -LocalAddress $TargetIP `
  -RemoteAddress $AllowedSubnet -Profile Any
Set-Service sshd -StartupType Automatic
Start-Service sshd
Get-Service sshd
```

Inspect other allow rules that might still expose port 22 on other interfaces. If your environment already uses SSH for other things, adjust the policy deliberately rather than blindly disabling existing access.

## 3. Create a dedicated non-admin SSH user

Use Windows' account management interface or Administrator PowerShell to create a dedicated **non-administrator** account with a long unique password. Do not use a passwordless account. Do not grant local administrator privileges just for telemetry.

Windows Hello PIN is not an SSH password. Prefer **SSH public-key authentication** for automated monitoring.

## 4. Verify the SSH server's host key

On the Windows target (local Administrator PowerShell):

```powershell
ssh-keygen -lf "$env:ProgramData\ssh\ssh_host_ed25519_key.pub"
```

On the Linux controller, connect using your account and actual Windows target address:

```sh
ssh -l WINDOWS_SSH_USER WINDOWS_PRIVATE_IP
```

Compare the fingerprints and accept only the expected host key. If the same IP was reassigned, investigate the mismatch instead of skipping the check.

## 5. Configure public-key authentication

On Linux, locate the **public** SSH key. Never share its matching private key:

```sh
cat "$HOME/.ssh/id_ed25519.pub"
```

For a **non-administrator** Windows SSH account, install the public key into the target user's `.ssh/authorized_keys` with appropriately restrictive permissions. An administrator account may be configured by Windows OpenSSH to read `%ProgramData%\ssh\administrators_authorized_keys` instead; a non-admin monitoring account avoids this extra complexity.

Verify you can execute a fixed read-only command without a password prompt:

```sh
ssh -l WINDOWS_SSH_USER WINDOWS_PRIVATE_IP hostname
```

The controller requires that the host key has already been accepted; it uses `StrictHostKeyChecking=yes` and `BatchMode=yes` for the actual probes.

## 6. Register Windows in ATHENA-04

```sh
./athena node add demo-windows WINDOWS_PRIVATE_IP WINDOWS_SSH_USER windows
./athena node check demo-windows
```

Alternatively use the web UI's `+ ADD` and choose Windows, or select an existing node and use the `OS` button. The CLI reads the *fixed* PowerShell source from `windows/windows-probe.ps1` at runtime and encodes it as UTF-16LE/Base64 for `-EncodedCommand`. Start the controller from a trusted repository root. The probe does not grant Windows administrative access.

## Troubleshooting

- `Connection timed out` — check the SSH service, firewall and private network.
- `Permission denied` — check the account and key authorization (not NixOS packages).
- `ATHENA Windows probe failed` — record the first *sanitized* error and check Windows PowerShell compatibility; do not grant admin privileges as a workaround.

**Never publish actual `authorized_keys`, private keys, SSH logs with private topology, user-specific paths, or screenshots of your machine.**

Official references:
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse?pivots=windows-11
- https://learn.microsoft.com/en-us/windows-server/administration/OpenSSH/openssh-server-configuration
- https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement
