[CmdletBinding()]
param([switch]$CheckOnly, [switch]$VarySounds)
$ErrorActionPreference = 'Stop'
try {
    if ($CheckOnly -and $VarySounds) { throw 'Choose either a read-only check or sound variation.' }
    $games = @(Get-Process -Name MySimsKingdom -ErrorAction SilentlyContinue)
    if ($games.Count -ne 1) { throw 'Start exactly one copy of MySims Kingdom, load your save, and stand beside Ms. Prissykins first.' }
    Add-Type -Path (Join-Path $PSScriptRoot 'PrissykinsMemory.cs')
    $result = [PrissykinsMemory]::Run($games[0].Id, $CheckOnly.IsPresent)
    if ($VarySounds) { $result = $result.Replace(' You can close this window.', '') }
    Write-Host $result -ForegroundColor Green
    if ($VarySounds) { [PrissykinsMemory]::VarySounds($games[0].Id) }
} catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    exit 1
}
