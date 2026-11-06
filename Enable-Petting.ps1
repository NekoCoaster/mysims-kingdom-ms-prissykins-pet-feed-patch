[CmdletBinding()]
param([switch]$CheckOnly)
$ErrorActionPreference = 'Stop'
try {
    $games = @(Get-Process -Name MySimsKingdom -ErrorAction SilentlyContinue)
    if ($games.Count -ne 1) { throw 'Start exactly one copy of MySims Kingdom, load your save, and stand beside Ms. Prissykins first.' }
    Add-Type -Path (Join-Path $PSScriptRoot 'PrissykinsMemory.cs')
    $result = [PrissykinsMemory]::Run($games[0].Id, $CheckOnly.IsPresent)
    Write-Host $result -ForegroundColor Green
} catch {
    Write-Host $_.Exception.GetBaseException().Message -ForegroundColor Red
    exit 1
}
