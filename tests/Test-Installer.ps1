# Uses a synthetic script and a mocked executable hash; never touches a game install.
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
$projectRoot = Split-Path -Parent $PSScriptRoot
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('prissykins-installer-test-' + [guid]::NewGuid().ToString('N'))
$luaFolder = Join-Path $fixtureRoot 'data\GameData\Lua'
New-Item -ItemType Directory -Path $luaFolder -Force | Out-Null
$fixtureExe = Join-Path $fixtureRoot 'MySimsKingdom.exe'
$fixtureLua = Join-Path $luaFolder 'CatAnimal.lua'
$global:PrissykinsTestUnsupported = $false
[IO.File]::WriteAllText($fixtureExe, 'Synthetic test fixture, not an executable.')
$original = "local CatAnimal = {} `r`nCatAnimal._instanceVars =`r`n{`r`n    example = true,`r`n}`r`nCatAnimal.interactionSet = System:CopyShallow(Classes.HerdableScriptObjectBase.interactionSet)`r`n"
[IO.File]::WriteAllText($fixtureLua, $original)
function Get-Process { param($Name, $ErrorAction) return @() }
function Get-FileHash {
    param($LiteralPath, $Algorithm)
    if ([IO.Path]::GetFileName($LiteralPath) -eq 'MySimsKingdom.exe') {
        if ($global:PrissykinsTestUnsupported) { return [pscustomobject]@{Hash='UNSUPPORTED-FIXTURE'} }
        return [pscustomobject]@{Hash='F7AD84B5D5DAC73EE4E777590324D99E5A6E1F2B0C0CFDA69C448E50B9495B2A'}
    }
    Microsoft.PowerShell.Utility\Get-FileHash -LiteralPath $LiteralPath -Algorithm SHA256
}
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot
if ($LASTEXITCODE -eq 1) { throw 'Installation returned an error.' }
$installed = [IO.File]::ReadAllText($fixtureLua)
if ($installed -notmatch 'bPetWhenNotHerded = true,') { throw 'Setting not installed.' }
if ($installed -notmatch 'BEGIN Prissykins follow/stay') { throw 'Follow/stay script not installed.' }
if ([IO.File]::ReadAllText("$fixtureLua.prissykins-backup") -cne $original) { throw 'Backup differs from original.' }
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot
if ($LASTEXITCODE -eq 1) { throw 'Repeat installation returned an error.' }
if ([IO.File]::ReadAllText($fixtureLua) -cne $installed) { throw 'Repeated installation changed the script.' }
[IO.File]::AppendAllText($fixtureLua, '-- later user edit')
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot -Uninstall
if ($LASTEXITCODE -ne 1) { throw 'Uninstall should have refused a later edit.' }
if ([IO.File]::ReadAllText($fixtureLua) -notmatch 'later user edit') { throw 'Uninstall overwrote a later edit.' }
[IO.File]::WriteAllText($fixtureLua, $installed)
$global:LASTEXITCODE = 0
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot -Uninstall
if ($LASTEXITCODE -eq 1) { throw 'Uninstall returned an error.' }
if ([IO.File]::ReadAllText($fixtureLua) -cne $original) { throw 'Uninstall did not restore original bytes.' }
$oldInstall = $original.Replace('    example', "    bPetWhenNotHerded = true,`r`n    example")
[IO.File]::WriteAllText($fixtureLua, $oldInstall)
$global:LASTEXITCODE = 0
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot
if ($LASTEXITCODE -eq 1 -or [IO.File]::ReadAllText("$fixtureLua.prissykins-backup") -cne $oldInstall) { throw 'Manually enabled flag was not preserved as the restore point.' }
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot -Uninstall
if ($LASTEXITCODE -eq 1 -or [IO.File]::ReadAllText($fixtureLua) -cne $oldInstall) { throw 'Manually enabled flag was not restored.' }
[IO.File]::WriteAllText("$fixtureLua.prissykins-backup", $original)
@{ OriginalHash = (Get-FileHash -LiteralPath "$fixtureLua.prissykins-backup").Hash; InstalledHash = (Get-FileHash -LiteralPath $fixtureLua).Hash } |
    ConvertTo-Json | Set-Content -LiteralPath "$fixtureLua.prissykins-install.json" -Encoding UTF8
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot
if ($LASTEXITCODE -eq 1 -or [IO.File]::ReadAllText($fixtureLua) -notmatch 'BEGIN Prissykins follow/stay') { throw 'Upgrade from the old installer failed.' }
if ([IO.File]::ReadAllText("$fixtureLua.prissykins-backup") -cne $original) { throw 'Upgrade replaced the original backup.' }
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot -Uninstall
if ($LASTEXITCODE -eq 1 -or [IO.File]::ReadAllText($fixtureLua) -cne $original) { throw 'Upgrade restoration failed.' }
[IO.File]::WriteAllText($fixtureLua, $original)
$global:PrissykinsTestUnsupported = $true
& (Join-Path $projectRoot 'Install.ps1') -GameRoot $fixtureRoot
if ($LASTEXITCODE -ne 1 -or [IO.File]::ReadAllText($fixtureLua) -cne $original) { throw 'Unsupported version was not rejected cleanly.' }
Write-Host 'PASS: installation, repeat installation, later-edit protection, exact restoration, manual flag preservation, v0.2 upgrade, unsupported version.'
Write-Host "Synthetic fixtures retained at $fixtureRoot"
exit 0
