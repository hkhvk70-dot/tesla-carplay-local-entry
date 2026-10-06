# SPDX-License-Identifier: GPL-3.0-only
# Requires PowerShell 7. Build only: does not install or start the app.
[CmdletBinding()]
param(
    [string]$AndroidSdkRoot = $env:ANDROID_SDK_ROOT,
    [string]$JavaHome = $env:JAVA_HOME,
    [string]$BuildToolsVersion = '36.0.0',
    [int]$CompileSdk = 36,
    [switch]$Unsigned
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $AndroidSdkRoot) { $AndroidSdkRoot = $env:ANDROID_HOME }
if (-not $AndroidSdkRoot) { throw 'Set ANDROID_SDK_ROOT or pass -AndroidSdkRoot.' }
if (-not $JavaHome) { throw 'Set JAVA_HOME or pass -JavaHome with a JDK installation.' }
$AndroidSdkRoot = (Resolve-Path -LiteralPath $AndroidSdkRoot).Path
$JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
$toolsRoot = Join-Path $AndroidSdkRoot "build-tools/$BuildToolsVersion"
$androidJar = Join-Path $AndroidSdkRoot "platforms/android-$CompileSdk/android.jar"
$executableSuffix = if ($IsWindows) { '.exe' } else { '' }
$batchSuffix = if ($IsWindows) { '.bat' } else { '' }
$javac = Join-Path $JavaHome "bin/javac$executableSuffix"
$jar = Join-Path $JavaHome "bin/jar$executableSuffix"
$keytool = Join-Path $JavaHome "bin/keytool$executableSuffix"
$aapt = Join-Path $toolsRoot "aapt2$executableSuffix"
$zipalign = Join-Path $toolsRoot "zipalign$executableSuffix"
$d8 = Join-Path $toolsRoot "d8$batchSuffix"
$apksigner = Join-Path $toolsRoot "apksigner$batchSuffix"
foreach ($requiredPath in @($androidJar, $javac, $jar, $aapt, $zipalign, $d8, $apksigner)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Missing tool or SDK file: $requiredPath"
    }
}

function Invoke-BuildTool {
    param([string]$Tool, [string[]]$ToolArguments)
    & $Tool @ToolArguments
    if ($LASTEXITCODE -ne 0) { throw "Build tool failed: $(Split-Path -Leaf $Tool) (exit $LASTEXITCODE)" }
}

& (Join-Path $PSScriptRoot 'verify-source.ps1')
$buildRoot = Join-Path $repoRoot 'build'
# A separate directory per invocation prevents stale class/DEX inclusion.
$workRoot = Join-Path $buildRoot ([guid]::NewGuid().ToString('N'))
$classesRoot = Join-Path $workRoot 'classes'
$dexRoot = Join-Path $workRoot 'dex'
New-Item -ItemType Directory -Path $classesRoot, $dexRoot -Force | Out-Null
$javaSources = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'app/src/main/java') -Filter '*.java' -Recurse | Select-Object -ExpandProperty FullName)
$previousJavaHome = $env:JAVA_HOME
try {
    $env:JAVA_HOME = $JavaHome
    Invoke-BuildTool $javac (@('-J-Dfile.encoding=UTF-8', '-encoding', 'UTF-8', '-Xlint:-options', '--release', '8', '-classpath', $androidJar, '-d', $classesRoot) + $javaSources)
    $classFiles = @(Get-ChildItem -LiteralPath $classesRoot -Filter '*.class' -Recurse | Select-Object -ExpandProperty FullName)
    Invoke-BuildTool $d8 (@('--lib', $androidJar, '--min-api', '26', '--output', $dexRoot) + $classFiles)
    $rawApk = Join-Path $workRoot 'raw.apk'
    $alignedApk = Join-Path $buildRoot 'CarPlay-Local-Entry-0.4.0-unsigned.apk'
    Invoke-BuildTool $aapt @('link', '--manifest', (Join-Path $repoRoot 'app/src/main/AndroidManifest.xml'), '-I', $androidJar, '--min-sdk-version', '26', '--target-sdk-version', '36', '-o', $rawApk)
    Invoke-BuildTool $jar @('--update', '--file', $rawApk, '-C', $dexRoot, 'classes.dex')
    Invoke-BuildTool $zipalign @('-f', '-p', '4', $rawApk, $alignedApk)
    Invoke-BuildTool $zipalign @('-c', '-p', '4', $alignedApk)
    $outputApk = $alignedApk
    if (-not $Unsigned) {
        if (-not (Test-Path -LiteralPath $keytool -PathType Leaf)) { throw 'JDK keytool is required for a debug-signed build.' }
        $keyRoot = Join-Path $repoRoot '.local'
        $debugKeystore = Join-Path $keyRoot 'debug.keystore'
        New-Item -ItemType Directory -Path $keyRoot -Force | Out-Null
        if (-not (Test-Path -LiteralPath $debugKeystore -PathType Leaf)) {
            Invoke-BuildTool $keytool @('-genkeypair', '-keystore', $debugKeystore, '-alias', 'androiddebugkey', '-storepass', 'android', '-keypass', 'android', '-dname', 'CN=Android Debug,O=Android,C=US', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '10000')
        }
        $outputApk = Join-Path $buildRoot 'CarPlay-Local-Entry-0.4.0-debug.apk'
        Invoke-BuildTool $apksigner @('sign', '--ks', $debugKeystore, '--ks-key-alias', 'androiddebugkey', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', $outputApk, $alignedApk)
        Invoke-BuildTool $apksigner @('verify', '--verbose', $outputApk)
    }
    $hash = (Get-FileHash -LiteralPath $outputApk -Algorithm SHA256).Hash
    [pscustomobject]@{ Apk = $outputApk; Sha256 = $hash; SignedForDevelopment = -not $Unsigned } | ConvertTo-Json
} finally {
    $env:JAVA_HOME = $previousJavaHome
}
