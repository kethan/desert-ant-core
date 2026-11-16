# Build a portable Windows x64 Clear CLI after build-clear-node.ps1 has staged
# its dependencies. The model is a separate file and is never downloaded by the CLI.
$ErrorActionPreference = 'Stop'
$native = 'packages/clear-node/native/win32-x64'
if (-not (Test-Path "$native/ClearNode.dll")) { throw 'Run Tools/windows/build-clear-node.ps1 first' }
$env:DAL_CLEAR_CLI_BUILD = '1'
try {
    & swift build --scratch-path .build-clear-node -c release --product ClearCLI --disable-default-traits
    if ($LASTEXITCODE -ne 0) { throw 'ClearCLI build failed' }
    $bin = (& swift build --scratch-path .build-clear-node -c release --show-bin-path).Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Cannot locate Swift build output' }
} finally { Remove-Item Env:DAL_CLEAR_CLI_BUILD -ErrorAction SilentlyContinue }
$dest = '.build-clear-portable'
Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $dest | Out-Null
Copy-Item "$bin/ClearCLI.exe" "$dest/clear.exe"
Copy-Item "$native/*.dll" $dest
Copy-Item LICENSE.md, THIRD_PARTY_NOTICES.md $dest
Copy-Item Tools/windows/clear-cli/README.txt $dest

# Walk the executable's PE imports too. The Node core and CLI share most, but
# not necessarily all, Swift runtime dependencies. Never copy system DLLs.
$target = (& swift -print-target-info | Out-String | ConvertFrom-Json)
$dirs = @($bin, $native, 'Vendor/litert/lib/windows-x64', 'Vendor/onnxruntime/lib/windows-x64') + @($target.paths.runtimeLibraryPaths) + ($env:Path -split ';')
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $dest 'clear.exe'))
Get-ChildItem $dest -Filter *.dll | ForEach-Object { $queue.Enqueue($_.FullName) }
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
