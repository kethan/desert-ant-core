# Stage a Windows x64, installation-free Clear + Node + FFmpeg folder.
# Run after the Clear Node build, workspace npm install, and native model test.
$ErrorActionPreference = 'Stop'
$dest = '.build-enhance-portable'
$native = 'packages/clear-node/native/win32-x64'
$model = 'packages/clear-node/test/.model-cache/clear-studio.tflite'
foreach ($file in @("$native/ClearNode.dll", $model, 'node_modules/koffi/build/koffi/win32_x64/koffi.node')) {
    if (-not (Test-Path $file)) { throw "Missing $file: build and test the Clear Node native first" }
}
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
$core = "$dest/node_modules/@desert-ant-labs/core"
$clear = "$dest/node_modules/@desert-ant-labs/clear"
$koffi = "$dest/node_modules/koffi"
New-Item -ItemType Directory -Force -Path $dest, $core, $clear, "$koffi/build/koffi/win32_x64", "$dest/model", "$dest/THIRD-PARTY/Node", "$dest/THIRD-PARTY/Koffi", "$dest/THIRD-PARTY/FFmpeg" | Out-Null
Set-Content -Path "$dest/package.json" -Value '{"private":true,"type":"module"}'
Copy-Item Tools/windows/enhance-portable/enhance.js, Tools/windows/enhance-portable/README.txt, enhance.mjs, LICENSE.md, THIRD_PARTY_NOTICES.md $dest
$node = (Get-Command node.exe).Source
Copy-Item $node "$dest/node.exe"
$nodeVersion = (& $node --version).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Could not determine Node version' }
# The official Node LICENSE covers Node and its bundled dependencies.
$nodeLicense = Join-Path (Split-Path $node) 'LICENSE'
if (Test-Path $nodeLicense) { Copy-Item $nodeLicense "$dest/THIRD-PARTY/Node/LICENSE" }
else { Invoke-WebRequest -Uri "https://raw.githubusercontent.com/nodejs/node/$nodeVersion/LICENSE" -OutFile "$dest/THIRD-PARTY/Node/LICENSE" }
Copy-Item js/*.js, js/package.json $core
Copy-Item js/src "$core/src" -Recurse
Copy-Item packages/clear-node/*.js, packages/clear-node/package.json $clear
New-Item -ItemType Directory -Force "$clear/native" | Out-Null
Copy-Item $native "$clear/native/win32-x64" -Recurse
Copy-Item node_modules/koffi/index.js, node_modules/koffi/package.json, node_modules/koffi/LICENSE.txt $koffi
Copy-Item node_modules/koffi/build/koffi/win32_x64/koffi.node "$koffi/build/koffi/win32_x64/"
Copy-Item node_modules/koffi/LICENSE.txt "$dest/THIRD-PARTY/Koffi/LICENSE.txt"
Copy-Item $model "$dest/model/clear-studio.tflite"

# FFmpeg and FFprobe are separate GPL programs. Pin an upstream static build
# and verify its digest; preserve its accompanying documentation and source
# references rather than silently relying on a machine-wide installation.
$url = 'https://github.com/FFmpeg-Builds/FFmpeg-Builds/releases/download/autobuild-2026-11-16-15-29/ffmpeg-n8.1.3-35-gf1acb0a266-win64-gpl-8.1.zip'
$sha256 = '83f357ea3c48ea6371388cfd1c6d3a8ddc1e23f4d87f645de1ab1c259fbcf78e'
$tmp = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
New-Item -ItemType Directory $tmp | Out-Null
try {
    $zip = Join-Path $tmp 'ffmpeg.zip'
    Write-Host "Downloading pinned FFmpeg build: $url"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $url -OutFile $zip
    if ((Get-FileHash $zip -Algorithm SHA256).Hash.ToLowerInvariant() -ne $sha256) { throw 'FFmpeg archive checksum mismatch' }
    $extract = Join-Path $tmp 'extracted'
    New-Item -ItemType Directory $extract | Out-Null
    & tar.exe -xf $zip -C $extract
    if ($LASTEXITCODE -ne 0) { throw 'Could not extract FFmpeg archive' }
    $root = Get-ChildItem $extract -Directory | Select-Object -First 1
    if (-not $root) { throw 'FFmpeg archive has no root directory' }
    foreach ($name in @('ffmpeg.exe', 'ffprobe.exe')) {
        $src = Join-Path $root.FullName "bin/$name"
        if (-not (Test-Path $src)) { throw "FFmpeg archive is missing $name" }
        Copy-Item $src $dest
    }
    Get-ChildItem $root.FullName | Where-Object { $_.Name -ne 'bin' } | ForEach-Object {
        Copy-Item $_.FullName "$dest/THIRD-PARTY/FFmpeg/" -Recurse -Force
    }
    @(
        'FFmpeg and FFprobe are separately distributed GPL programs.',
        "Upstream binary archive: $url",
        "Archive SHA256: $sha256",
        'Upstream build scripts and license/source information: https://github.com/FFmpeg-Builds/FFmpeg-Builds',
        'FFmpeg source: https://github.com/FFmpeg/FFmpeg/tree/f1acb0a266',
        'Review upstream documentation and GPL obligations before redistributing this bundle.'
    ) | Set-Content "$dest/THIRD-PARTY/FFmpeg/BUILD-INFO.txt"
} finally { Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue }
Write-Host "Portable bundle staged in $dest"
