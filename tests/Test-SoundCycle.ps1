$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'PrissykinsMemory.cs')
$cycle = New-Object PrissykinsMemory+VoiceCycle
if ($cycle.Ready(100, 0)) { throw 'A new voice must settle before changing its next choice.' }
if ($cycle.Ready(100, 79)) { throw 'Voice settled too early.' }
if (-not $cycle.Ready(100, 80)) { throw 'Stable voice was not eligible.' }
$cycle.MarkHandled(100)
if ($cycle.Ready(100, 1000)) { throw 'The same voice was handled twice.' }
if ($cycle.Ready(101, 1000)) { throw 'New voice inherited previous timing.' }
if (-not $cycle.Ready(101, 1080)) { throw 'Next voice was not eligible.' }
for ($id = 102; $id -lt 500; $id++) { $null = $cycle.Ready($id, 2000) }
if (-not $cycle.Ready(499, 2080)) { throw 'Recent voice lost its tracking state.' }
Write-Host 'PASS: settling interval, once per voice, next voice, bounded history.'
