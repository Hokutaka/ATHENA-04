# ATHENA-04 Windows v0.6.2: local Win32 API telemetry via read-only calls.
# Avoid CIM/WMI permission requirements for the dedicated non-admin SSH account.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

# GlobalMemoryStatusEx and GetTickCount64 work without admin elevation.
# MEMORYSTATUSEX mirrors the Windows sysinfoapi.h definition exactly.
$interop = @'
using System;
using System.Runtime.InteropServices;

public static class Athena04Native {
    [StructLayout(LayoutKind.Sequential)]
    public struct MemoryStatus {
        public UInt32 dwLength;
        public UInt32 dwMemoryLoad;
        public UInt64 ullTotalPhys;
        public UInt64 ullAvailPhys;
        public UInt64 ullTotalPageFile;
        public UInt64 ullAvailPageFile;
        public UInt64 ullTotalVirtual;
        public UInt64 ullAvailVirtual;
        public UInt64 ullAvailExtendedVirtual;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GlobalMemoryStatusEx(ref MemoryStatus buffer);

    [DllImport("kernel32.dll")]
    public static extern UInt64 GetTickCount64();
}
'@

try {
    Add-Type -TypeDefinition $interop -ErrorAction Stop
    $mem = [Athena04Native+MemoryStatus]::new()
    # MEMORYSTATUSEX: 2 DWORDs (4 bytes each) + 7 ULONGLONGs (8 bytes each) = 64 bytes.
    # Avoid the PowerShell 5.1 Marshal.SizeOf([type]) overload issue.
    $mem.dwLength = [uint32]64
    if (-not [Athena04Native]::GlobalMemoryStatusEx([ref]$mem)) {
        throw 'GlobalMemoryStatusEx returned failure'
    }
    $uptimeSeconds = [math]::Floor([Athena04Native]::GetTickCount64() / 1000.0)
    $memTotalKiB = [math]::Floor($mem.ullTotalPhys / 1024.0)
    $memAvailableKiB = [math]::Floor($mem.ullAvailPhys / 1024.0)

    Write-Output 'OS: Windows'
    Write-Output ('Hostname: ' + [Environment]::MachineName)
    Write-Output ('Kernel: ' + [Environment]::OSVersion.VersionString)
    Write-Output ('Machine: ' + $env:PROCESSOR_ARCHITECTURE)
    Write-Output ('CPUs: ' + [Environment]::ProcessorCount)
    Write-Output ('Uptime: ' + $uptimeSeconds)
    Write-Output ('MemTotal: ' + $memTotalKiB + ' kB')
    Write-Output ('MemAvailable: ' + $memAvailableKiB + ' kB')
    Write-Output 'Probe: ATHENA-WINDOWS-3'
} catch {
    [Console]::Error.WriteLine('ATHENA Windows probe failed: ' + $_.Exception.Message)
    exit 2
}
