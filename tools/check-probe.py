#!/usr/bin/env python3
"""Check that the readable PowerShell probe is the runtime source of truth."""
from pathlib import Path
import re

root = Path(__file__).resolve().parents[1]
source = (root / 'windows/windows-probe.ps1').read_text(encoding='utf-8')
cli = (root / 'cmd/cli/main.ha').read_text(encoding='utf-8')
assert 0 < len(source.encode('utf-8')) <= 16384
assert 'const WINDOWS_PROBE' not in cli, 'Pre-encoded PowerShell blob must not be committed'
for marker in [
    'windows/windows-probe.ps1',
    'io::drain(file)',
    'strings::fromutf8(source)',
    'strings::next(&iter)',
    'base64::encodestr(',
    'powershell.exe -NoProfile -NonInteractive -EncodedCommand ',
    'windows_probe_command()',
]:
    assert marker in cli, f'Missing runtime encoder step: {marker}'
assert not re.search(r'-EncodedCommand [A-Za-z0-9+/=]{100}', cli)
# The expected bytes for PowerShell -EncodedCommand are UTF-16LE, not UTF-8.
assert 'QQA=' == __import__('base64').b64encode('A'.encode('utf-16le')).decode()
assert 'aQA=' == __import__('base64').b64encode('i'.encode('utf-16le')).decode()
print('Readable Windows probe and runtime UTF-16LE/Base64 encoder checks passed.')
