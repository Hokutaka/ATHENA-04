#!/usr/bin/env python3
from pathlib import Path

s = Path('windows/windows-probe.ps1').read_text(encoding='utf-8')
assert '    $mem.dwLength = [uint32]64' in s, 'MEMORYSTATUSEX dwLength not set'
assert 'Marshal]::SizeOf(' not in s, 'PowerShell overload bug reintroduced'
assert "'Probe: ATHENA-WINDOWS-3'" in s
assert s.count('public UInt32 ') == 2
assert s.count('public UInt64 ull') == 7
assert "[Athena04Native]::GlobalMemoryStatusEx([ref]$mem)" in s
print('Windows MEMORYSTATUSEX layout static checks passed (64 bytes).')
