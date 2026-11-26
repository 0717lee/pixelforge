# Dot-source from PowerShell: . ./scripts/use-toolchain.ps1
param(
  [string]$Toolchain = (Join-Path $env:USERPROFILE '.moon/toolchains/1.0.0-rc1')
)

$compiler = Join-Path $Toolchain 'bin/moonc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
  throw "Install MoonBit 1.0.0-rc1+3c0520448 at $Toolchain or pass -Toolchain PATH."
}
$version = & $compiler -v
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v1\.0\.0-rc1\+3c0520448(?:\s|$)') {
  throw "Expected moonc 1.0.0-rc1+3c0520448, got: $version"
}
$env:MOON_HOME = (Resolve-Path -LiteralPath $Toolchain).Path
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
Write-Output $version
