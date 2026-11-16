# Build and stage the Windows x64 Clear Node core and its non-system DLLs.
# Requires Swift, Git Bash, Python 3.12, and the MSVC developer tools on PATH.
$ErrorActionPreference = 'Stop'
& Tools/windows/vendor-litert.ps1
if ($LASTEXITCODE -ne 0) { throw 'LiteRT vendoring failed' }
# Inference links COnnxRuntime on Windows even for LiteRT models like Clear.
# Reuse the same pinned wheel and import-library helper as the Swift CI job.
& bash -c 'source Tools/dal.sh && dal_vendor_onnxruntime'
if ($LASTEXITCODE -ne 0) { throw 'ONNX Runtime vendoring failed (requires Git Bash and the Swift LLVM tools)' }
# SwiftPM exports the model's C entry point but does not export the shared
# NativeBindings module's @_cdecl functions from a Windows dynamic product.
# /EXPORT both retains and exports each ABI symbol, even in optimized builds.
$abi = @(
    'clear_create', 'dal_is_downloaded', 'dal_download', 'dal_run',
    'dal_destroy', 'dal_flush_telemetry', 'dal_buffer_free',
    'dal_set_log_level', 'dal_set_logger', 'dal_set_license_verifier'
)
$linkFlags = @()
foreach ($symbol in $abi) { $linkFlags += @('-Xlinker', "/EXPORT:$symbol") }
& swift build --scratch-path .build-clear-node -c release --product ClearNode --disable-default-traits @linkFlags
if ($LASTEXITCODE -ne 0) { throw 'ClearNode build failed' }
$bin = (& swift build --scratch-path .build-clear-node -c release --show-bin-path).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot locate Swift build output' }
$dest = 'packages/clear-node/native/win32-x64'
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item "$bin/ClearNode.dll" $dest
# Fail at build time if any ABI symbol is missing, before the Node/model test.
$exports = & dumpbin /exports (Join-Path $dest 'ClearNode.dll')
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect ClearNode.dll exports' }
foreach ($symbol in $abi) {
    if (-not ($exports | Where-Object { $_ -match "\s$([regex]::Escape($symbol))\s*$" })) {
        throw "ClearNode.dll is missing required export $symbol"
    }
}
Copy-Item 'Vendor/litert/lib/windows-x64/libLiteRt.dll' $dest
# System32 may contain an older onnxruntime.dll. Always stage the version we
# linked, even if dumpbin's dependency walk finds the system copy first.
Copy-Item 'Vendor/onnxruntime/lib/windows-x64/onnxruntime.dll' $dest

# Follow PE imports, staging toolchain and build-output DLLs rather than relying
# on Swift being installed on the consumer machine. System DLLs are never copied.
$target = (& swift -print-target-info | Out-String | ConvertFrom-Json)
$dirs = @($bin, 'Vendor/litert/lib/windows-x64') + @($target.paths.runtimeLibraryPaths) + ($env:Path -split ';')
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $dest 'ClearNode.dll'))
$queue.Enqueue((Join-Path $dest 'libLiteRt.dll'))
$queue.Enqueue((Join-Path $dest 'onnxruntime.dll'))
$seen = @{}
while ($queue.Count -gt 0) {
    $file = $queue.Dequeue()
    $key = [IO.Path]::GetFileName($file).ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    $imports = & dumpbin /dependents $file
    if ($LASTEXITCODE -ne 0) { throw "dumpbin failed for $file" }
    foreach ($line in $imports) {
        if ($line -notmatch '^\s+([^\s]+\.dll)\s*$') { continue }
        $name = $Matches[1]
        if (Test-Path (Join-Path $env:SystemRoot "System32/$name")) { continue }
        if ($name -match '^(api-ms-win-|ext-ms-win-)') { continue }
        $staged = Join-Path $dest $name
        if (-not (Test-Path $staged)) {
            $source = $null
            foreach ($dir in $dirs) {
                if ($dir -and (Test-Path (Join-Path $dir $name))) { $source = Join-Path $dir $name; break }
            }
            if (-not $source) { throw "Cannot locate dependency $name imported by $file" }
            Copy-Item $source $staged
        }
        $queue.Enqueue($staged)
    }
}
Get-ChildItem $dest
