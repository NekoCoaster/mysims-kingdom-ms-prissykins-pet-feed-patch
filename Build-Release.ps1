[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$files = @(
    '.gitattributes', '.gitignore', '.github/workflows/check.yml',
    'README.md', 'RESEARCH.md', 'LICENSE', 'Build-Release.ps1',
    'PrissykinsMemory.cs', 'Enable-Petting.ps1', 'Enable Petting.cmd',
    'Install.ps1', 'Install.cmd', 'Uninstall.cmd', 'tests/Test-Installer.ps1',
    'docs/images/prissykins-petting-demo.gif'
)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$zipPath = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path 'Prissykins-Petting-0.1.0.zip'
if (Test-Path -LiteralPath $zipPath) { throw "Release already exists: $zipPath. Choose a fresh output directory." }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::Open($zipPath, 'Create')
try {
    foreach ($relative in $files) {
        $source = Join-Path $PSScriptRoot $relative
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
        if ($actual -ne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $relative)).Hash) { throw "ZIP verification failed: $relative" }
    }
} finally { $archive.Dispose() }
$hash = (Get-FileHash -LiteralPath $zipPath).Hash
"$hash  $([IO.Path]::GetFileName($zipPath))" | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ASCII
Write-Host "Verified $($files.Count) files: $zipPath"
Write-Host "SHA-256: $hash"
