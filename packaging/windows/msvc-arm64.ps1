# Load Visual Studio's ARM64 C++ tools into this process. native-wheels.ps1 runs it (not dot-sourced):
# $env: changes are process-wide, so the compiler stays on PATH for the wheel build that follows.
# Windows on Arm has to compile capstone and pygfxd here; PyPI publishes no win_arm64 wheel for either.
$ErrorActionPreference = 'Stop'

$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
if (-not (Test-Path -LiteralPath $vswhere)) {
    $vswhere = Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe'
}
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw 'Visual Studio is not installed (vswhere.exe is missing). Windows on Arm wheel builds need the C++ tools.'
}
$install = (& $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath | Select-Object -First 1)
if (-not $install) {
    throw 'Visual Studio C++ tools for ARM64 were not found. Install the MSVC ARM64 build tools (the windows-11-arm runner includes them).'
}
$devShell = Join-Path $install 'Common7\Tools\Microsoft.VisualStudio.DevShell.dll'
if (-not (Test-Path -LiteralPath $devShell)) {
    throw "Visual Studio DevShell is missing: $devShell"
}
Import-Module $devShell
Enter-VsDevShell -VsInstallPath $install -SkipAutomaticLocation -DevCmdArguments '-arch=arm64 -host_arch=arm64'
# setuptools uses the compiler already on PATH instead of looking up an x64 toolset
$env:DISTUTILS_USE_SDK = '1'
$env:MSSdk = '1'
$cmake = Join-Path $install 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin'
if (Test-Path -LiteralPath (Join-Path $cmake 'cmake.exe')) {
    $env:PATH = "$cmake;$env:PATH"
}
foreach ($tool in @('cl.exe', 'nmake.exe', 'cmake.exe')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH after the ARM64 developer shell. capstone's build runs cmake -G NMake and needs all three."
    }
}
