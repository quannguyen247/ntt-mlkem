$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$vivado = 'C:\AMDDesignTools\2025.2.1\Vivado\bin\vivado.bat'
$buildTcl = Join-Path $scriptDir 'create_kv260_debug.tcl'
$log = Join-Path $scriptDir 'build.log'
$journal = Join-Path $scriptDir 'build.jou'

if (-not (Test-Path -LiteralPath $vivado)) {
    throw "Vivado not found at $vivado"
}

& $vivado -mode batch -source $buildTcl -log $log -journal $journal
if ($LASTEXITCODE -ne 0) {
    throw "Vivado build failed. Read $log"
}

$bit = Join-Path $scriptDir 'output\ntt_kv260_debug.bit'
if (-not (Test-Path -LiteralPath $bit)) {
    throw "Build finished without producing $bit"
}

Write-Host "Build complete:"
Write-Host $bit
