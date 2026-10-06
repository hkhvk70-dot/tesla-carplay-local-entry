# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$expected = @(
    '.gitattributes', '.gitignore', '.github/workflows/build.yml',
    'LICENSE', 'NOTICE', 'README.md',
    'app/src/main/AndroidManifest.xml',
    'app/src/main/java/local/carplay/localentry/MainActivity.java',
    'app/src/main/java/local/carplay/localentry/LocalEntryService.java',
    'docs/SETUP.zh-CN.md', 'docs/TECHNICAL.md', 'docs/VALIDATION.md',
    'patches/wheelplay/README.md',
    'patches/wheelplay/0001-manual-hotspot-ipv4.patch',
    'patches/wheelplay/0002-stable-direct-credentials.patch',
    'scripts/build.ps1', 'scripts/verify-source.ps1'
)

$sourceFiles = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Force | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/')
    if ($relative -notmatch '^(?:\.git|build|\.local)/') { $relative }
})
$unexpected = @($sourceFiles | Where-Object { $_ -notin $expected })
$missing = @($expected | Where-Object { $_ -notin $sourceFiles })
if ($unexpected.Count -or $missing.Count) {
    throw "Source allowlist mismatch. Unexpected: $($unexpected -join ', '); Missing: $($missing -join ', ')"
}

# Also reject an ignored local/build artifact that was explicitly tracked by mistake.
if (Test-Path -LiteralPath (Join-Path $repoRoot '.git')) {
    $trackedFiles = @(& git -C $repoRoot ls-files)
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the Git index.' }
    $extraTracked = @($trackedFiles | Where-Object { $_ -notin $expected })
    if ($extraTracked.Count) { throw "Unexpected tracked publication files: $($extraTracked -join ', ')" }
}

$privateMaterialPattern = '-----' + 'BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
$localUserPathPattern = 'C:' + '\\Users\\'
foreach ($relative in $sourceFiles) {
    $content = [IO.File]::ReadAllText((Join-Path $repoRoot $relative))
    if ($content -match $privateMaterialPattern -or $content -match $localUserPathPattern) {
        throw "Private material or a personal Windows path detected in: $relative"
    }
    if ($relative -match '\.(?:ps1)$') {
        $tokens = $null
        $parseErrors = $null
        [Management.Automation.Language.Parser]::ParseInput($content, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count) { throw "PowerShell parse failure in $relative" }
    }
}

[xml]$manifest = Get-Content -LiteralPath (Join-Path $repoRoot 'app/src/main/AndroidManifest.xml') -Raw
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$permissions = @($manifest.manifest.'uses-permission' | ForEach-Object { $_.GetAttribute('name', $androidNamespace) })
$allowedPermissions = @(
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_SPECIAL_USE',
    'android.permission.POST_NOTIFICATIONS'
)
if (@($permissions | Where-Object { $_ -notin $allowedPermissions }).Count) { throw 'Unexpected runtime permission in manifest.' }
if ($manifest.manifest.application.service.GetAttribute('permission', $androidNamespace) -ne 'android.permission.BIND_VPN_SERVICE') {
    throw 'VPN service must be protected by BIND_VPN_SERVICE.'
}
Write-Output "Source verification passed: $($sourceFiles.Count) allowlisted files; no unexpected runtime permissions."
