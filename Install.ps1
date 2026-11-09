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
    $bundledDll = Join-Path $PSScriptRoot 'winmm.dll'
    if (-not (Test-Path -LiteralPath $bundledDll -PathType Leaf)) { throw 'winmm.dll is missing. Extract the entire ZIP before running Install.cmd.' }
    $dll = Join-Path $GameRoot 'winmm.dll'
    $bundledDllHash = (Get-FileHash -LiteralPath $bundledDll).Hash
    $currentDllHash = if (Test-Path -LiteralPath $dll) { (Get-FileHash -LiteralPath $dll).Hash }
    $knownDllHashes = @(
        'D6E8543964251C92D6EFDB5621B36690B24813EF5CC630E634B94BF33F52A343' # v0.2.0 and v0.3.0
        '3E3FF0072F8FB6AE0469589D7C63B9ED41CF714C0503F3B8701CDAAA7BA1A81B' # original travel test
        'BD120AFED39ABEFEE51AD95D6EF4CED8DC73D76B862CD163548CA27A529CC52E' # travel tests 3 and 4
    )
    $installDll = $currentDllHash -ne $bundledDllHash
    if ($installDll -and $currentDllHash -and $currentDllHash -notin $knownDllHashes) {
        throw 'An unrecognized winmm.dll is already installed. It may belong to another mod. Nothing changed.'
    }
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
    $installScript = -not ($hasRecord -and $text.TrimEnd().EndsWith($payload, [StringComparison]::Ordinal))
    if (-not $installScript -and -not $installDll) {
        Write-Host 'The travel test is already installed. No files changed.' -ForegroundColor Green
        exit 0
    }
    if ($installScript) {
        if ($hasRecord) {
            $previousPayload = [regex]::Match($text.TrimEnd(), '(?ms)^-- BEGIN Prissykins follow/stay\r?\n.*^-- END Prissykins follow/stay\z')
            if ($previousPayload.Success) {
                $normalized = $previousPayload.Value -replace '\r\n', "`n"
                $sha = [Security.Cryptography.SHA256]::Create()
                try { $payloadHash = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($normalized))).Replace('-', '') }
                finally { $sha.Dispose() }
            # Accept verified v0.3.0 and earlier travel test payloads.
            if ($payloadHash -in @(
                '171A183FD92DC721DAEE0E952F858C0157B74FD467ABEA6E25A33F6FDB835C06',
                'B5623864C474011F4DB158E9D03FB9FBAAA78391DA83D3396CCE406D84D5207F',
                'E20ADCBFC05EDBB456CBE55328C39B2C6205FDEE7A29056C8C8D1D345DCEE7D8'
            )) {
                    $text = $text.Substring(0, $previousPayload.Index)
                }
            }
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
    }

    # Stage both files and keep the old copies until the manifest is committed.
    $token = [Guid]::NewGuid().ToString('N')
    $nextScript = "$path.$token.new"
    $nextManifest = "$manifest.$token.new"
    $rollback = "$path.$token.rollback"
    $nextDll = "$dll.$token.new"
    $dllRollback = "$dll.$token.rollback"
    $madeBackup = $false
    $addedDll = $false
    $committed = $false
    try {
        if ($installDll) {
            [IO.File]::Copy($bundledDll, $nextDll, $false)
            if ((Get-FileHash -LiteralPath $nextDll).Hash -ne $bundledDllHash) { throw 'DLL copy verification failed.' }
        }
        if ($installScript) {
            [IO.File]::WriteAllBytes($nextScript, $bytes)
            $record | ConvertTo-Json | Set-Content -LiteralPath $nextManifest -Encoding UTF8
        }
        if ((Get-FileHash -LiteralPath $path).Hash -ne $currentHash) { throw 'CatAnimal.lua changed during setup. Try again after reviewing it.' }
        if ($installScript) {
            if (-not $hasRecord) {
                [IO.File]::Copy($path, $backup, $false)
                $madeBackup = $true
            }
            [IO.File]::Replace($nextScript, $path, $rollback)
            if ((Get-FileHash -LiteralPath $path).Hash -ne $record.InstalledHash) { throw 'Installation verification failed.' }
        }
        $liveDllHash = if (Test-Path -LiteralPath $dll) { (Get-FileHash -LiteralPath $dll).Hash }
        if ($liveDllHash -ne $currentDllHash) { throw 'winmm.dll changed during setup. Try again after reviewing it.' }
        if ($installDll) {
            if ($currentDllHash) { [IO.File]::Replace($nextDll, $dll, $dllRollback) }
            else {
                [IO.File]::Move($nextDll, $dll)
                $addedDll = $true
            }
            if ((Get-FileHash -LiteralPath $dll).Hash -ne $bundledDllHash) { throw 'DLL installation verification failed.' }
        }
        if ($installScript) {
            if ($hasRecord) { [IO.File]::Replace($nextManifest, $manifest, [NullString]::Value) }
            else { [IO.File]::Move($nextManifest, $manifest) }
        }
        $committed = $true
    } catch {
        try {
            if (Test-Path -LiteralPath $rollback) { [IO.File]::Replace($rollback, $path, [NullString]::Value) }
            if ($madeBackup) { Remove-Item -LiteralPath $backup }
        } finally {
            if (Test-Path -LiteralPath $dllRollback) { [IO.File]::Replace($dllRollback, $dll, [NullString]::Value) }
            elseif ($addedDll) { Remove-Item -LiteralPath $dll }
        }
        throw
    } finally {
        foreach ($file in @($nextScript, $nextManifest, $nextDll)) {
            if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
        }
        if ($committed) {
            foreach ($file in @($rollback, $dllRollback)) {
                if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file }
            }
        }
    }
    Write-Host 'Travel test installed. Launch MySims Kingdom through Steam.' -ForegroundColor Green
} catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    Write-Host 'If Windows denied access to the game folder, use Run as administrator on the installer.'
    exit 1
}
