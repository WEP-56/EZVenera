param(
    [string]$ProjectRoot = 'D:\venera\EZVenera',
    [string]$OutputRoot = 'D:\venera\pack',
    [string]$NsisPath = 'C:\Program Files (x86)\NSIS\makensis.exe',
    [switch]$SkipWindows,
    [switch]$SkipAndroid
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PubspecVersion {
    param([string]$PubspecPath)

    $content = Get-Content -Path $PubspecPath -Raw
    $match = [regex]::Match($content, '(?m)^version:\s*([0-9A-Za-z\.\-_]+)\+([0-9A-Za-z\.\-_]+)\s*$')
    if (-not $match.Success) {
        throw "Failed to parse version from $PubspecPath"
    }

    return @{
        Name = $match.Groups[1].Value
        Build = $match.Groups[2].Value
        Full = "$($match.Groups[1].Value)+$($match.Groups[2].Value)"
    }
}

function Get-NsisCompiler {
    param([string]$PreferredPath)

    $candidates = @(
        $PreferredPath,
        'C:\Program Files (x86)\NSIS\makensis.exe',
        'C:\Program Files\NSIS\makensis.exe'
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    throw 'NSIS is not installed. Expected makensis.exe at the configured path or in a standard installation path.'
}

function Ensure-Directory {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Invoke-FlutterBuild {
    param(
        [string]$ProjectRoot,
        [string[]]$Arguments
    )

    Push-Location $ProjectRoot
    try {
        & flutter @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Flutter command failed: flutter $($Arguments -join ' ')"
        }
    }
    finally {
        Pop-Location
    }
}

function Build-WindowsSetup {
    param(
        [string]$ProjectRoot,
        [string]$OutputRoot,
        [string]$NsisPath,
        [hashtable]$Version
    )

    $makensisPath = Get-NsisCompiler -PreferredPath $NsisPath
    $windowsOutput = Join-Path $ProjectRoot 'build\windows\x64\runner\Release'
    $nsiPath = Join-Path $ProjectRoot 'scripts\windows_installer.nsi'
    $setupBaseName = "EZVenera-$($Version.Name)-windows-setup"

    Invoke-FlutterBuild -ProjectRoot $ProjectRoot -Arguments @('build', 'windows', '--release')

    if (-not (Test-Path $windowsOutput)) {
        throw "Windows release output not found: $windowsOutput"
    }

    if (-not (Test-Path $nsiPath)) {
        throw "NSIS script not found: $nsiPath"
    }

    & $makensisPath `
        "/DMyAppVersion=$($Version.Name)" `
        "/DMySourceDir=$windowsOutput" `
        "/DMyOutputDir=$OutputRoot" `
        "/DMyOutputBaseFilename=$setupBaseName" `
        $nsiPath
    if ($LASTEXITCODE -ne 0) {
        throw 'NSIS compilation failed.'
    }

    $artifact = Join-Path $OutputRoot "$setupBaseName.exe"
    if (-not (Test-Path $artifact)) {
        throw "Windows setup artifact not found: $artifact"
    }

    return $artifact
}

function Build-AndroidApk {
    param(
        [string]$ProjectRoot,
        [string]$OutputRoot,
        [hashtable]$Version
    )

    # Per-ABI APKs (armeabi-v7a + arm64-v8a) — same layout as CI releases.
    Invoke-FlutterBuild -ProjectRoot $ProjectRoot -Arguments @(
        'build', 'apk', '--release', '--split-per-abi',
        '--target-platform', 'android-arm,android-arm64'
    )

    $abis = @('armeabi-v7a', 'arm64-v8a')
    $targets = [System.Collections.Generic.List[string]]::new()
    foreach ($abi in $abis) {
        $apkSource = Join-Path $ProjectRoot "build\app\outputs\flutter-apk\app-$abi-release.apk"
        if (-not (Test-Path $apkSource)) {
            throw "Android APK not found for ABI $abi : $apkSource"
        }
        $apkTarget = Join-Path $OutputRoot "EZVenera-$($Version.Name)-android-$abi-release.apk"
        Copy-Item -Path $apkSource -Destination $apkTarget -Force
        $targets.Add($apkTarget)
    }
    # Legacy alias for pre-1.8.3 in-app updater (endsWith android-release.apk).
    $legacy = Join-Path $OutputRoot "EZVenera-$($Version.Name)-android-release.apk"
    $arm64 = Join-Path $OutputRoot "EZVenera-$($Version.Name)-android-arm64-v8a-release.apk"
    Copy-Item -Path $arm64 -Destination $legacy -Force
    $targets.Add($legacy)
    return $targets
}

$version = Get-PubspecVersion -PubspecPath (Join-Path $ProjectRoot 'pubspec.yaml')

Ensure-Directory -Path $OutputRoot

$artifacts = [System.Collections.Generic.List[string]]::new()

if (-not $SkipWindows) {
    $artifacts.Add((Build-WindowsSetup -ProjectRoot $ProjectRoot -OutputRoot $OutputRoot -NsisPath $NsisPath -Version $version))
}

if (-not $SkipAndroid) {
    foreach ($apk in (Build-AndroidApk -ProjectRoot $ProjectRoot -OutputRoot $OutputRoot -Version $version)) {
        $artifacts.Add($apk)
    }
}

Write-Host ''
Write-Host "Build completed for EZVenera $($version.Full)"
foreach ($artifact in $artifacts) {
    Write-Host "Artifact: $artifact"
}
