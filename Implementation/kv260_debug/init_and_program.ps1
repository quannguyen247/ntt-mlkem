$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$xsct = 'C:\AMDDesignTools\2025.2.1\Vitis\bin\xsct.bat'
$programTcl = Join-Path $scriptDir 'init_and_program.tcl'

if (-not (Test-Path -LiteralPath $xsct)) {
    throw "XSCT not found at $xsct"
}

& $xsct $programTcl
if ($LASTEXITCODE -ne 0) {
    throw 'KV260 initialization/programming failed.'
}
