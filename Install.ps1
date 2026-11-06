[CmdletBinding()]
param([string]$GameRoot, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
try {
    if (-not $GameRoot) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select MySimsKingdom.exe in your Steam game folder'
        $dialog.Filter = 'MySims Kingdom|MySimsKingdom.exe'
        $dialog.InitialDirectory = "${env:ProgramFiles(x86)}\Steam\steamapps\common\MySims Kingdom"
        if ($dialog.ShowDialog() -ne 'OK') { Write-Host 'Cancelled. Nothing changed.'; exit 0 }
        $GameRoot = Split-Path -Parent $dialog.FileName
    }
    $GameRoot = (Resolve-Path -LiteralPath $GameRoot).Path
    $exe = Join-Path $GameRoot 'MySimsKingdom.exe'
    $path = Join-Path $GameRoot 'data\GameData\Lua\CatAnimal.lua'
    $backup = "$path.prissykins-backup"
    $manifest = "$path.prissykins-install.json"
    if (@(Get-Process -Name MySimsKingdom -ErrorAction SilentlyContinue).Count) { throw 'Close MySims Kingdom before installing or uninstalling.' }
    if (-not (Test-Path -LiteralPath $exe) -or -not (Test-Path -LiteralPath $path)) { throw 'This is not a supported MySims Kingdom game folder.' }
    if ($Uninstall) {
        if (-not (Test-Path -LiteralPath $manifest)) { Write-Host 'No change made by this installer was found. Your existing CatAnimal.lua is untouched.'; exit 0 }
        $record = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ((Get-FileHash -LiteralPath $path).Hash -ne $record.InstalledHash) { throw 'CatAnimal.lua changed after installation. Restore your backup manually after reviewing those changes.' }
        if ((Get-FileHash -LiteralPath $backup).Hash -ne $record.OriginalHash) { throw 'The original backup does not match its recorded hash. Nothing was restored.' }
        Copy-Item -LiteralPath $backup -Destination $path
        Remove-Item -LiteralPath $manifest
        Remove-Item -LiteralPath $backup
        Write-Host 'Original CatAnimal.lua restored. Fully restart the game to clear the temporary interaction registration.' -ForegroundColor Green
        exit 0
    }
    $supported = 'F7AD84B5D5DAC73EE4E777590324D99E5A6E1F2B0C0CFDA69C448E50B9495B2A'
    if ((Get-FileHash -LiteralPath $exe).Hash -ne $supported) { throw 'Unsupported game executable. This release supports Steam build 21152538 only.' }
    $original = [IO.File]::ReadAllBytes($path)
    $text = [Text.Encoding]::UTF8.GetString($original)
    if ($text -match '(?m)^\s*bPetWhenNotHerded\s*=\s*true\s*,?\s*$') {
        Write-Host 'The always-available setting is already present. No files changed.' -ForegroundColor Green
        exit 0
    }
    if ($text -match 'bPetWhenNotHerded') { throw 'CatAnimal.lua already mentions bPetWhenNotHerded with a different setting. Review it manually before installation.' }
    if ((Test-Path -LiteralPath $backup) -or (Test-Path -LiteralPath $manifest)) { throw 'An earlier installation backup exists. Review it before installing again.' }
    $pattern = '(CatAnimal\._instanceVars\s*=\s*\{)'
    if ([regex]::Matches($text, $pattern).Count -ne 1) { throw 'Unexpected CatAnimal.lua layout. Nothing changed.' }
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $replacement = '$1' + $newline + '    bPetWhenNotHerded = true,'
    $updated = [regex]::Replace($text, $pattern, $replacement)
    $encoding = New-Object Text.UTF8Encoding($false)
    $bytes = $encoding.GetBytes($updated)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $record = [ordered]@{
            OriginalHash = [BitConverter]::ToString($sha.ComputeHash($original)).Replace('-', '')
            InstalledHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
        }
    } finally { $sha.Dispose() }
    [IO.File]::WriteAllBytes($backup, $original)
    $record | ConvertTo-Json | Set-Content -LiteralPath $manifest -Encoding UTF8
    [IO.File]::WriteAllBytes($path, $bytes)
    if ((Get-FileHash -LiteralPath $path).Hash -ne $record.InstalledHash) { throw 'Installation verification failed. The original file is in CatAnimal.lua.prissykins-backup.' }
    Write-Host 'Installed and backed up the original script. Start the game, stand beside Ms. Prissykins, then run Enable Petting.cmd.' -ForegroundColor Green
} catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    Write-Host 'If Windows denied access to the game folder, use Run as administrator on the installer.'
    exit 1
}
