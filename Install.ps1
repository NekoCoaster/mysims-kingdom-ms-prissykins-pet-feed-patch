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
    $payload = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'CatFollowStay.lua') -Raw
    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $payload = $payload.TrimEnd() -replace '\r?\n', $newline
    $hasRecord = Test-Path -LiteralPath $manifest
    $hasBackup = Test-Path -LiteralPath $backup
    if ($hasRecord -ne $hasBackup) { throw 'The previous installer backup is incomplete. Review it before installing again.' }
    $currentHash = (Get-FileHash -LiteralPath $path).Hash
    $originalHash = $currentHash
    if ($hasRecord) {
        $previous = Get-Content -LiteralPath $manifest -Raw | ConvertFrom-Json
        if ($currentHash -ne $previous.InstalledHash -or
            (Get-FileHash -LiteralPath $backup).Hash -ne $previous.OriginalHash) {
            throw 'The installed script or its backup has changed since setup. Review those changes before upgrading.'
        }
        $originalHash = $previous.OriginalHash
    }
    if ($text.TrimEnd().EndsWith($payload, [StringComparison]::Ordinal) -and $hasRecord) {
        Write-Host 'Follow and Stay are already installed. No files changed.' -ForegroundColor Green
        exit 0
    }
    if ($text -match 'Prissykins follow/stay|prissykinsControl') { throw 'An unrecognized follow/stay patch is present. Restore the previous script before installing.' }
    if ($text -match '(?m)^\s*function\s+CatAnimal:(?!EnterTriggerCallback\b)') {
        throw 'CatAnimal.lua has custom callbacks that may conflict. Nothing changed.'
    }
    if ($text -notmatch '(?m)^\s*bPetWhenNotHerded\s*=\s*true\s*,?\s*$') {
        if ($text -match 'bPetWhenNotHerded') { throw 'CatAnimal.lua already mentions bPetWhenNotHerded with a different setting. Review it manually before installation.' }
        $pattern = '(CatAnimal\._instanceVars\s*=\s*\{)'
        if ([regex]::Matches($text, $pattern).Count -ne 1) { throw 'Unexpected CatAnimal.lua layout. Nothing changed.' }
        $text = [regex]::Replace($text, $pattern, '$1' + $newline + '    bPetWhenNotHerded = true,')
    }
    if ($text -notmatch '(?m)^CatAnimal\.interactionSet\s*=\s*System:CopyShallow\(') {
        throw 'Unexpected CatAnimal.lua interaction layout. Nothing changed.'
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($text.TrimEnd() + $newline + $newline + $payload + $newline)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $record = [ordered]@{
            OriginalHash = $originalHash
            InstalledHash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '')
        }
    } finally { $sha.Dispose() }

    # Prepare both files before replacing the live script. Keep the old script
    # until the manifest is committed so an upgrade can be rolled back on error.
    $token = [Guid]::NewGuid().ToString('N')
    $nextScript = "$path.$token.new"
    $nextManifest = "$manifest.$token.new"
    $rollback = "$path.$token.rollback"
    $madeBackup = $false
    $committed = $false
    try {
        [IO.File]::WriteAllBytes($nextScript, $bytes)
        $record | ConvertTo-Json | Set-Content -LiteralPath $nextManifest -Encoding UTF8
        if ((Get-FileHash -LiteralPath $path).Hash -ne $currentHash) { throw 'CatAnimal.lua changed during setup. Try again after reviewing it.' }
        if (-not $hasRecord) {
            [IO.File]::Copy($path, $backup, $false)
            $madeBackup = $true
        }
        [IO.File]::Replace($nextScript, $path, $rollback)
        if ((Get-FileHash -LiteralPath $path).Hash -ne $record.InstalledHash) { throw 'Installation verification failed.' }
        if ($hasRecord) { [IO.File]::Replace($nextManifest, $manifest, [NullString]::Value) }
        else { [IO.File]::Move($nextManifest, $manifest) }
        $committed = $true
    } catch {
        if (Test-Path -LiteralPath $rollback) { [IO.File]::Replace($rollback, $path, [NullString]::Value) }
        if ($madeBackup) { Remove-Item -LiteralPath $backup }
        throw
    } finally {
        foreach ($file in @($nextScript, $nextManifest)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        }
        if ($committed -and (Test-Path -LiteralPath $rollback)) { Remove-Item -LiteralPath $rollback }
    }
    Write-Host 'Follow and Stay installed. Keep winmm.dll beside MySimsKingdom.exe and start through Steam. Feed to follow and Pet to stay after the tower quest.' -ForegroundColor Green
} catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    Write-Host 'If Windows denied access to the game folder, use Run as administrator on the installer.'
    exit 1
}
