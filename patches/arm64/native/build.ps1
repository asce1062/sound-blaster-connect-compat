# Cross-compile the arm64-v8a native libs with the Android NDK and stage them
# into the arm64 patch overlay. Run from anywhere; paths resolve off this file.
#
#   pwsh patches/arm64/native/build.ps1
#
# Override the SDK/NDK/ABI via environment or -Param if the defaults are wrong.
param(
    [string]$Sdk     = "$env:LOCALAPPDATA\Android\Sdk",
    [string]$NdkVer  = "25.1.8937393",
    [string]$CmakeVer = "3.22.1",
    [string]$Abi     = "arm64-v8a",
    [string]$Platform = "android-21"
)
$ErrorActionPreference = "Stop"

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$overlay = Join-Path (Split-Path -Parent $here) "overlay\lib\$Abi"
$build   = Join-Path $here "build\$Abi"

$cmake   = Join-Path $Sdk "cmake\$CmakeVer\bin\cmake.exe"
$ninja   = Join-Path $Sdk "cmake\$CmakeVer\bin\ninja.exe"
$toolchain = Join-Path $Sdk "ndk\$NdkVer\build\cmake\android.toolchain.cmake"

foreach ($p in @($cmake, $ninja, $toolchain)) {
    if (-not (Test-Path $p)) { throw "not found: $p" }
}

New-Item -ItemType Directory -Force -Path $build, $overlay | Out-Null

& $cmake -S $here -B $build -G Ninja `
    "-DCMAKE_MAKE_PROGRAM=$ninja" `
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain" `
    "-DANDROID_ABI=$Abi" `
    "-DANDROID_PLATFORM=$Platform" `
    "-DCMAKE_BUILD_TYPE=Release"
if ($LASTEXITCODE -ne 0) { throw "configure failed" }

& $cmake --build $build
if ($LASTEXITCODE -ne 0) { throw "build failed" }

Get-ChildItem -Path $build -Recurse -Filter *.so | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $overlay $_.Name) -Force
    Write-Host "staged $($_.Name) -> $overlay"
}
