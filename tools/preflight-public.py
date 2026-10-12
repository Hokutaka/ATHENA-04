#!/usr/bin/env python3
"""Conservative pre-publish scan. Does not replace manual review."""
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
IGNORED = {'.git', '.build-v062', 'build', '.ssh', '__pycache__', '.vscode', '.idea'}
CODE_EXT = {'.md', '.sh', '.ha', '.js', '.css', '.html', '.nix', '.py', '.txt', '.json', '.yml', '.yaml', '.mjs', '.ps1'}
PATTERNS = {
    'private key block': re.compile(r'-----BEGIN (?:OPENSSH|RSA|EC|DSA) PRIVATE KEY-----'),
    'absolute Linux home path': re.compile(r'/home/[A-Za-z0-9_.-]+/'),
    'absolute Windows user path': re.compile(r'C:\\Users\\[A-Za-z0-9_.-]+\\', re.I),
    'potential GitHub access token': re.compile(r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}'),
    'literal credential assignment': re.compile(r'(?im)^\s*(?:password|api[_-]?key|secret|token)\s*[:=]\s*[\x22\x27]?[A-Za-z0-9+/_=-]{16,}'),
}
# Guard against lab IPs hardcoded into docs/tests. 127.0.0.1 is deliberately permitted,
# as are the RFC 5737 examples 192.0.2.0/24, 198.51.100.0/24, 203.0.113.0/24.
IPV4 = re.compile(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])')

def forbidden_ip(ip: str) -> bool:
    parts = [int(x) for x in ip.split('.')]
    if any(x > 255 for x in parts):
        return False
    a,b,c,d = parts
    if a == 127 or (a,b,c) in ((192,0,2),(198,51,100),(203,0,113)):
        return False
    return a == 10 or (a == 172 and 16 <= b <= 31) or (a == 192 and b == 168)

# In a Git checkout, inspect tracked files plus untracked, non-ignored files.
# This includes staged files but excludes build artifacts ignored by .gitignore.
has_git = (ROOT / '.git').exists()
tracked_names = []
if has_git:
    tracked_result = subprocess.run(
        ['git', '-C', str(ROOT), 'ls-files', '--cached', '-z'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    tracked_names = [name for name in tracked_result.stdout.decode('utf-8').split('\0') if name]
    candidates_result = subprocess.run(
        ['git', '-C', str(ROOT), 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True,
    )
    candidates = [ROOT / name for name in
                  candidates_result.stdout.decode('utf-8').split('\0') if name]
else:
    candidates = list(ROOT.rglob('*'))

findings = []
for path in sorted(set(candidates)):
    if not path.is_file() or any(p in IGNORED for p in path.relative_to(ROOT).parts):
        continue
    relative = path.relative_to(ROOT)
    if path.suffix.lower() not in CODE_EXT and path.name not in {'.gitignore', '.gitattributes', 'LICENSE', 'COPYING'}:
        findings.append((str(relative), 'unexpected file (review manually)'))
        continue
    text = path.read_text(encoding='utf-8')
    for label, regex in PATTERNS.items():
        if regex.search(text):
            findings.append((str(relative), label))
    for ip in set(IPV4.findall(text)):
        if forbidden_ip(ip):
            findings.append((str(relative), 'private address in tracked text'))

# Check index entries as well: a tracked secret file must never be silently
# skipped merely because its directory is ignored by the working-tree scan.
# This checks the Git index, not historical commits.
if has_git:
    for name in tracked_names:
        parts = Path(name).parts
        base = Path(name).name
        if (
            '.ssh' in parts
            or base == 'nodes.tsv' or base.startswith('nodes.tsv.')
            or base == '.env' or base.startswith('.env.')
            or base in {'authorized_keys', 'known_hosts', 'administrators_authorized_keys'}
            or base.startswith(('id_ed25519', 'id_rsa', 'id_ecdsa'))
            or name.startswith('.config/athena-04/')
        ):
            findings.append((name, 'sensitive runtime/environment file is tracked'))
if findings:
    for path, label in findings:
        print(f'REVIEW REQUIRED: {path}: {label}')
    sys.exit(1)
print('Public preflight OK: no flagged credentials, home paths, private IPs, or unexpected files.')
print('Manual review, commit metadata inspection and git history review are still required.')
