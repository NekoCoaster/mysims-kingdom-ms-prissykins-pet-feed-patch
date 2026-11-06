[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ZigPath)
$ErrorActionPreference='Stop'
$exports = @(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'winmm-exports.json') -Raw | ConvertFrom-Json)
$asm = [Collections.Generic.List[string]]::new()
$defs = [Collections.Generic.List[string]]::new()
$names = [Collections.Generic.List[string]]::new()
$ordinals = [Collections.Generic.List[string]]::new()
$asm.Add('.text')
$defs.Add('LIBRARY winmm')
$defs.Add('EXPORTS')
for ($i=0; $i -lt $exports.Count; $i++) {
    $e=$exports[$i]; $symbol="proxy_export_$i"; $slow=".Lresolve_$i"
    if ($e.name) { $defs.Add("$($e.name)=$symbol @$($e.ordinal)"); $names.Add('"'+$e.name+'"') }
    else { $defs.Add("$symbol @$($e.ordinal) NONAME"); $names.Add('nullptr') }
    $ordinals.Add([string]$e.ordinal)
    foreach($line in @(".globl $symbol", ".p2align 4", ".seh_proc $symbol", "${symbol}:",
        "movq g_targets+$($i*8)(%rip), %rax", 'testq %rax, %rax', "jz $slow", 'jmp *%rax', "${slow}:",
        'subq $168, %rsp', '.seh_stackalloc 168', '.seh_endprologue',
        'movq %rcx, 32(%rsp)', 'movq %rdx, 40(%rsp)', 'movq %r8, 48(%rsp)', 'movq %r9, 56(%rsp)',
        'movdqu %xmm0, 64(%rsp)', 'movdqu %xmm1, 80(%rsp)', 'movdqu %xmm2, 96(%rsp)',
        'movdqu %xmm3, 112(%rsp)', 'movdqu %xmm4, 128(%rsp)', 'movdqu %xmm5, 144(%rsp)',
        "movl `$$i, %ecx", 'call resolveWinmm',
        'movq 32(%rsp), %rcx', 'movq 40(%rsp), %rdx', 'movq 48(%rsp), %r8', 'movq 56(%rsp), %r9',
        'movdqu 64(%rsp), %xmm0', 'movdqu 80(%rsp), %xmm1', 'movdqu 96(%rsp), %xmm2',
        'movdqu 112(%rsp), %xmm3', 'movdqu 128(%rsp), %xmm4', 'movdqu 144(%rsp), %xmm5',
        'addq $168, %rsp', 'jmp *%rax', '.seh_endproc')) { $asm.Add($line) }
}
$ascii=[Text.Encoding]::ASCII
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'forwarders.S'),$asm,$ascii)
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'winmm.def'),$defs,$ascii)
$include="static constexpr unsigned ExportCount = $($exports.Count);`nstatic const char* ExportNames[] = {"+($names -join ',')+"};`nstatic const unsigned short ExportOrdinals[] = {"+($ordinals -join ',')+"};`n"
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'exports.inc'),$include,$ascii)
$output=Join-Path $PSScriptRoot 'build'
New-Item -ItemType Directory -Force $output | Out-Null
& $ZigPath c++ -target x86_64-windows-gnu -std=c++17 -O2 -shared -Wall -Wextra -Werror `
    (Join-Path $PSScriptRoot 'proxy.cpp') (Join-Path $PSScriptRoot 'forwarders.S') `
    (Join-Path $PSScriptRoot 'winmm.def') -lbcrypt -o (Join-Path $output 'winmm.dll')
if ($LASTEXITCODE -ne 0) { throw 'Proxy build failed.' }
Get-FileHash -LiteralPath (Join-Path $output 'winmm.dll') -Algorithm SHA256
