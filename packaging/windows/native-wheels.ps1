# Build the two extensions that publish no Windows on Arm wheel, from the source archives pinned in uv.lock.
# capstone stays on 5.0.9: the judge's disassembly text has to match the other platforms, and 6.x is different.
# pygfxd's sdist links with /DEF:pygfxd.def, but that file is not in the archive (the published win_amd64
# wheel's exports are written out here). tests/test_windows_host.py checks the urls and hashes against uv.lock.
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutDir
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
# The developer shell replaces PATH. Keep uv's path from before that.
$uv = (Get-Command uv).Source
if (-not $uv) { throw 'uv is not on PATH.' }
& (Join-Path $PSScriptRoot 'msvc-arm64.ps1')

# The exports of pygfxd 1.0.5's published win_amd64 libgfxd.so (a PE DLL named .so).
$pygfxdExports = @(
    'gfxd_arg_callbacks', 'gfxd_arg_count', 'gfxd_arg_dflt', 'gfxd_arg_fmt', 'gfxd_arg_fn',
    'gfxd_arg_name', 'gfxd_arg_type', 'gfxd_arg_valid', 'gfxd_arg_value', 'gfxd_cimg_callback',
    'gfxd_disable', 'gfxd_dl_callback', 'gfxd_dram_callback', 'gfxd_dynamic', 'gfxd_enable',
    'gfxd_endian', 'gfxd_execute', 'gfxd_f3d', 'gfxd_f3db', 'gfxd_f3dex', 'gfxd_f3dex2',
    'gfxd_f3dexb', 'gfxd_foreach_pkt', 'gfxd_input_buffer', 'gfxd_input_callback', 'gfxd_input_fd',
    'gfxd_light_callback', 'gfxd_lightsn_callback', 'gfxd_lookat_callback', 'gfxd_macro_data',
    'gfxd_macro_dflt', 'gfxd_macro_fn', 'gfxd_macro_id', 'gfxd_macro_name', 'gfxd_macro_offset',
    'gfxd_macro_packets', 'gfxd_mtx_callback', 'gfxd_output_buffer', 'gfxd_output_callback',
    'gfxd_output_fd', 'gfxd_print_value', 'gfxd_printf', 'gfxd_puts', 'gfxd_seg_callback',
    'gfxd_target', 'gfxd_timg_callback', 'gfxd_tlut_callback', 'gfxd_ucdata_callback',
    'gfxd_uctext_callback', 'gfxd_udata_get', 'gfxd_udata_set', 'gfxd_value_by_type',
    'gfxd_vp_callback', 'gfxd_vtx_callback', 'gfxd_write', 'gfxd_zimg_callback'
)

$sources = @(
    @{
        Name = 'capstone'
        Url = 'https://files.pythonhosted.org/packages/39/01/6516910f546fbb996068207b9dd0229b14bc8dae223114d5e0e27d3cad11/capstone-5.0.9.tar.gz'
        Sha256 = '0429af292ddc604d3c9344696807e281d5e728db029f00e6a4ea9e3bff1aac9e'
        Member = 'capstone\.dll|capstone\.pyd'
    },
    @{
        Name = 'pygfxd'
        Url = 'https://files.pythonhosted.org/packages/17/94/98ab685e4f62c39db84c2c5fed714e1c04bcbd934ccf35e231a5219946a7/pygfxd-1.0.5.tar.gz'
        Sha256 = 'b31f5f862dccc2e0faa605cc16cd63a22feb3244c07a2063037421fcd3f67145'
        Member = 'libgfxd\.so'
    }
)

$work = Join-Path ([IO.Path]::GetTempPath()) ("decomp-native-wheels-" + [guid]::NewGuid())
New-Item -ItemType Directory -Force $work | Out-Null
try {
    & $uv python install 3.12
    if ($LASTEXITCODE -ne 0) { throw "uv python install 3.12 failed with exit code $LASTEXITCODE" }
    $python = (& $uv python find 3.12).Trim()
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python)) {
        throw 'uv could not find Python 3.12 after installing it.'
    }
    $venv = Join-Path $work 'venv'
    & $uv venv --python $python $venv
    if ($LASTEXITCODE -ne 0) { throw "uv venv failed with exit code $LASTEXITCODE" }
    $py = Join-Path $venv 'Scripts\python.exe'
    # A throwaway environment, so setuptools is not installed into the app. uv run would try to
    # sync the project first, and that sync cannot install capstone on ARM until this wheel exists.
    & $uv pip install --python $py setuptools wheel
    if ($LASTEXITCODE -ne 0) { throw "Could not install setuptools for the wheel build (exit code $LASTEXITCODE)" }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    foreach ($source in $sources) {
        $archive = Join-Path $work ([IO.Path]::GetFileName($source.Url))
        curl.exe -L --fail --silent --show-error $source.Url -o $archive
        if ($LASTEXITCODE -ne 0) { throw "Could not download $($source.Name) (curl exit code $LASTEXITCODE)" }
        $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLower()
        if ($hash -ne $source.Sha256) { throw "$($source.Name) checksum mismatch: $hash" }
        $src = Join-Path $work $source.Name
        New-Item -ItemType Directory -Force $src | Out-Null
        tar.exe -xf $archive -C $src
        if ($LASTEXITCODE -ne 0) { throw "Could not unpack $($source.Name)" }
        $root = (Get-ChildItem -LiteralPath $src -Directory | Select-Object -First 1).FullName
        if (-not $root) { throw "$($source.Name) archive has no top directory" }
        if ($source.Name -eq 'pygfxd') {
            $def = Join-Path $root 'pygfxd.def'
            $lines = @('EXPORTS') + $pygfxdExports
            [IO.File]::WriteAllLines($def, $lines)
            # link.exe resolves /DEF relative to the build directory, not the source root
            $defFwd = $def.Replace('\', '/')
            $setupPath = Join-Path $root 'setup.py'
            $setup = [IO.File]::ReadAllText($setupPath)
            $patched = $setup.Replace('/DEF:pygfxd.def', "/DEF:$defFwd")
            if ($patched -eq $setup) { throw 'pygfxd setup.py has no /DEF:pygfxd.def to point at the generated module definition' }
            [IO.File]::WriteAllText($setupPath, $patched)
        }
        $dist = Join-Path $work ("dist-" + $source.Name)
        New-Item -ItemType Directory -Force $dist | Out-Null
        & $py (Join-Path $root 'setup.py') bdist_wheel --dist-dir $dist
        if ($LASTEXITCODE -ne 0) { throw "$($source.Name) wheel build failed with exit code $LASTEXITCODE" }
        $wheel = (Get-ChildItem -LiteralPath $dist -Filter '*.whl' | Select-Object -First 1).FullName
        if (-not $wheel) { throw "$($source.Name) produced no wheel" }
        $zip = [IO.Compression.ZipFile]::OpenRead($wheel)
        try {
            $hit = $zip.Entries | Where-Object { $_.FullName -match $source.Member }
            if (-not $hit) { throw "$wheel has no $($source.Member). The ARM64 compile did not produce the extension." }
        }
        finally { $zip.Dispose() }
        Copy-Item -LiteralPath $wheel -Destination $OutDir -Force
    }
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
