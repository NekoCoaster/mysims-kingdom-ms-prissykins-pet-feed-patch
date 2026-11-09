[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [ValidatePattern('^\d+\.\d+\.\d+(-[a-z0-9-]+(\.[a-z0-9-]+)*)?$')][string]$Version = '0.4.0-beta.1'
)
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $PSScriptRoot 'dist' }
$files = @(
    'README.md', 'LICENSE', 'Install.ps1', 'Install.cmd', 'Uninstall.cmd', 'CatFollowStay.lua',
    'winmm.dll',
    'third-party/Zig-LICENSE.txt', 'third-party/LLVM-LICENSE.txt', 'third-party/MinGW-COPYING.txt'
)
$dll = Join-Path $PSScriptRoot 'native/build/winmm.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw 'Build the proxy DLL with native/Build-Proxy.ps1 first.' }
$header = [IO.File]::ReadAllBytes($dll)
if ($header[0] -ne 0x4d -or $header[1] -ne 0x5a) { throw 'The proxy is not a Windows binary.' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zipPath = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path "Prissykins-Petting-$Version.zip"
if (Test-Path -LiteralPath $zipPath) { throw "Release already exists: $zipPath. Choose a fresh output directory." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($relative in $files) {
        $source = if ($relative -eq 'winmm.dll') { $dll } else { Join-Path $PSScriptRoot $relative }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $source, "Prissykins-Petting/$relative") | Out-Null
    }
} finally { $archive.Dispose() }
$archive = [IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    if ($archive.Entries.Count -ne $files.Count) { throw 'Unexpected archive contents.' }
    foreach ($relative in $files) {
        $entry = $archive.GetEntry("Prissykins-Petting/$relative")
        if ($null -eq $entry) { throw "Missing ZIP entry: $relative" }
        $stream = $entry.Open()
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $actual = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '') }
        finally { $sha.Dispose(); $stream.Dispose() }
        $source = if ($relative -eq 'winmm.dll') { $dll } else { Join-Path $PSScriptRoot $relative }
        if ($actual -ne (Get-FileHash -LiteralPath $source).Hash) { throw "ZIP verification failed: $relative" }
    }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath).Hash
"$hash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ASCII
Write-Host "Verified $($files.Count) files: $zipPath"
Write-Host "SHA-256: $hash"
