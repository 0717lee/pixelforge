# Dot-source from PowerShell: . ./scripts/use-toolchain.ps1
param(
  [string]$Toolchain = (Join-Path $env:USERPROFILE '.moon/toolchains/0.10.14')
)

$compiler = Join-Path $Toolchain 'bin/moonc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
  throw "Install MoonBit 0.10.14+7d59c7ec9 at $Toolchain or pass -Toolchain PATH."
}
$version = & $compiler -v
if ($LASTEXITCODE -ne 0 -or $version -notmatch '^v0\.10\.14\+7d59c7ec9(?:\s|$)') {
  throw "Expected moonc 0.10.14+7d59c7ec9, got: $version"
}
$env:MOON_HOME = (Resolve-Path -LiteralPath $Toolchain).Path
$env:PATH = (Join-Path $env:MOON_HOME 'bin') + [IO.Path]::PathSeparator + $env:PATH
Write-Output $version
