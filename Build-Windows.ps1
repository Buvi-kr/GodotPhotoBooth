param(
    [string]$Godot = (Join-Path $PSScriptRoot 'tools\godot\Godot_v4.7.2-stable_win64_console.exe'),
    [string]$ExportTemplate = (Join-Path $PSScriptRoot 'tools\godot\templates\windows_release_x86_64.exe'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'Build\Windows')
)

$ErrorActionPreference = 'Stop'
$project = $PSScriptRoot
$bridgeSource = Join-Path $project 'bin\camera-bridge\CameraBridge.exe'
$bridgeTargetDirectory = Join-Path $OutputDirectory 'CameraBridge'
$streamingTargetDirectory = Join-Path $OutputDirectory 'StreamingAssets'
$licenseTargetDirectory = Join-Path $OutputDirectory 'licenses'
$operationsTargetDirectory = Join-Path $OutputDirectory 'Operations'
$cloudflaredSource = Join-Path $project 'runtime\cloudflared.exe'
$cloudflaredTarget = Join-Path $streamingTargetDirectory 'cloudflared.exe'
$configSource = Join-Path $project 'data\config.json'
$configTarget = Join-Path $streamingTargetDirectory 'config.json'
$executable = Join-Path $OutputDirectory 'ArtValleyPhotoBooth.exe'
$stagingExecutable = Join-Path $OutputDirectory ('ArtValleyPhotoBooth-' + [guid]::NewGuid().ToString('N') + '.exe')

if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot 4.7.2 executable not found: $Godot"
}
if (-not (Test-Path -LiteralPath $ExportTemplate -PathType Leaf)) {
    throw "Godot 4.7.2 Windows release export template not found: $ExportTemplate"
}
$templateTarget = Join-Path $project 'tools\godot\templates\windows_release_x86_64.exe'
$templateTargetDirectory = Split-Path -Parent $templateTarget
if ((Resolve-Path -LiteralPath $ExportTemplate).Path -ne $templateTarget) {
    New-Item -ItemType Directory -Force -Path $templateTargetDirectory | Out-Null
    Copy-Item -LiteralPath $ExportTemplate -Destination $templateTarget -Force
}
if (-not (Test-Path -LiteralPath $cloudflaredSource -PathType Leaf)) {
    throw "cloudflared.exe is missing from the Godot runtime folder: $cloudflaredSource"
}

& $Godot --headless --path $project --script 'res://tools/generate_godot_notices.gd'
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $project 'licenses\Godot-Third-Party.txt'))) {
    throw 'Godot third-party license notice generation failed.'
}

& (Join-Path $project 'CameraBridge\build.ps1')
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $bridgeSource -PathType Leaf)) {
    throw 'CameraBridge build failed.'
}

New-Item -ItemType Directory -Force -Path $OutputDirectory,$bridgeTargetDirectory,$streamingTargetDirectory,$licenseTargetDirectory,$operationsTargetDirectory | Out-Null
try {
    & $Godot --headless --path $project --export-release 'Windows Desktop' $stagingExecutable
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $stagingExecutable -PathType Leaf)) {
        throw 'Godot Windows export failed. Existing package files were preserved.'
    }

    Move-Item -LiteralPath $stagingExecutable -Destination $executable -Force
}
finally {
    Remove-Item -LiteralPath $stagingExecutable,($stagingExecutable -replace '\.exe$','.tmp') -Force -ErrorAction SilentlyContinue
}

Copy-Item -LiteralPath $bridgeSource -Destination (Join-Path $bridgeTargetDirectory 'CameraBridge.exe') -Force
Copy-Item -LiteralPath $cloudflaredSource -Destination $cloudflaredTarget -Force
Copy-Item -LiteralPath $configSource -Destination $configTarget -Force
Copy-Item -LiteralPath (Join-Path $project 'LICENSE') -Destination (Join-Path $OutputDirectory 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $project 'LICENSES.md') -Destination (Join-Path $OutputDirectory 'LICENSES.md') -Force
Copy-Item -Path (Join-Path $project 'licenses\*') -Destination $licenseTargetDirectory -Force
Copy-Item -LiteralPath (Join-Path $project 'assets\fonts\NotoSansKR-OFL.txt') -Destination (Join-Path $licenseTargetDirectory 'NotoSansKR-OFL.txt') -Force
Copy-Item -LiteralPath (Join-Path $project 'OPERATOR_DASHBOARD.md'),(Join-Path $project 'Operator-Control.ps1'),(Join-Path $project 'Operator-Control.cmd') -Destination $operationsTargetDirectory -Force

$archivePath = Join-Path (Split-Path -Parent $OutputDirectory) 'ArtValleyPhotoBooth-Windows.zip'
$installerPath = Join-Path (Split-Path -Parent $OutputDirectory) 'ArtValleyPhotoBooth-Setup.exe'
$packageStageDirectory = Join-Path (Split-Path -Parent $OutputDirectory) ('PackageStage-' + [guid]::NewGuid().ToString('N'))
try {
    $stageBridgeDirectory = Join-Path $packageStageDirectory 'CameraBridge'
    $stageStreamingDirectory = Join-Path $packageStageDirectory 'StreamingAssets'
    $stageLicensesDirectory = Join-Path $packageStageDirectory 'licenses'
    $stageOperationsDirectory = Join-Path $packageStageDirectory 'Operations'
    New-Item -ItemType Directory -Force -Path $packageStageDirectory,$stageBridgeDirectory,$stageStreamingDirectory,$stageLicensesDirectory,$stageOperationsDirectory | Out-Null

    Copy-Item -LiteralPath $executable -Destination $packageStageDirectory
    Copy-Item -LiteralPath (Join-Path $OutputDirectory 'LICENSE'),(Join-Path $OutputDirectory 'LICENSES.md') -Destination $packageStageDirectory
    Copy-Item -LiteralPath (Join-Path $bridgeTargetDirectory 'CameraBridge.exe') -Destination $stageBridgeDirectory
    Copy-Item -LiteralPath $cloudflaredTarget,$configTarget -Destination $stageStreamingDirectory
    Copy-Item -LiteralPath (Join-Path $licenseTargetDirectory 'Apache-2.0.txt'),(Join-Path $licenseTargetDirectory 'Godot-MIT.txt'),(Join-Path $licenseTargetDirectory 'Godot-Third-Party.txt'),(Join-Path $licenseTargetDirectory 'NotoSansKR-OFL.txt') -Destination $stageLicensesDirectory
    Copy-Item -LiteralPath (Join-Path $operationsTargetDirectory 'OPERATOR_DASHBOARD.md'),(Join-Path $operationsTargetDirectory 'Operator-Control.ps1'),(Join-Path $operationsTargetDirectory 'Operator-Control.cmd') -Destination $stageOperationsDirectory

    Compress-Archive -Path (Join-Path $packageStageDirectory '*') -DestinationPath $archivePath -CompressionLevel Optimal -Force
}
finally {
    if (Test-Path -LiteralPath $packageStageDirectory) {
        $resolvedStage = (Resolve-Path -LiteralPath $packageStageDirectory).Path
        $resolvedStageParent = (Resolve-Path -LiteralPath (Split-Path -Parent $OutputDirectory)).Path
        if (-not $resolvedStage.StartsWith($resolvedStageParent,[StringComparison]::OrdinalIgnoreCase)) {
            throw 'Refusing to remove a package staging directory outside the output parent.'
        }
        Remove-Item -LiteralPath $resolvedStage -Recurse -Force
    }
}

$iexpress = Join-Path $env:WINDIR 'System32\iexpress.exe'
if (-not (Test-Path -LiteralPath $iexpress -PathType Leaf)) {
    throw "Windows IExpress was not found: $iexpress"
}
$installerStageDirectory = Join-Path (Split-Path -Parent $OutputDirectory) ('OneFileStage-' + [guid]::NewGuid().ToString('N'))
$installerSedPath = Join-Path (Split-Path -Parent $OutputDirectory) ('OneFile-' + [guid]::NewGuid().ToString('N') + '.sed')
try {
    New-Item -ItemType Directory -Force -Path $installerStageDirectory | Out-Null
    Copy-Item -LiteralPath $archivePath,(Join-Path $project 'installer\Install-FromBundle.ps1'),(Join-Path $project 'installer\Install-FromBundle.cmd') -Destination $installerStageDirectory
    $sed = @"
[Version]
Class=IEXPRESS
SEDVersion=3
[Options]
PackagePurpose=InstallApp
ShowInstallProgramWindow=0
HideExtractAnimation=1
UseLongFileName=1
InsideCompressed=0
CAB_FixedSize=0
CAB_ResvCodeSigning=0
RebootMode=N
InstallPrompt=%InstallPrompt%
DisplayLicense=%DisplayLicense%
FinishMessage=%FinishMessage%
TargetName=%TargetName%
FriendlyName=%FriendlyName%
AppLaunched=%AppLaunched%
PostInstallCmd=%PostInstallCmd%
AdminQuietInstCmd=%AdminQuietInstCmd%
UserQuietInstCmd=%UserQuietInstCmd%
SourceFiles=SourceFiles
[Strings]
InstallPrompt=
DisplayLicense=
FinishMessage=
TargetName=$installerPath
FriendlyName=Art Valley Photo Booth Setup
AppLaunched=cmd.exe /c Install-FromBundle.cmd
PostInstallCmd=<None>
AdminQuietInstCmd=<None>
UserQuietInstCmd=<None>
FILE0="ArtValleyPhotoBooth-Windows.zip"
FILE1="Install-FromBundle.ps1"
FILE2="Install-FromBundle.cmd"
[SourceFiles]
SourceFiles0=$installerStageDirectory
[SourceFiles0]
%FILE0%=
%FILE1%=
%FILE2%=
"@
    Set-Content -LiteralPath $installerSedPath -Value $sed -Encoding ASCII
    $iexpressProcess = Start-Process -FilePath $iexpress -ArgumentList @('/N','/Q',$installerSedPath) -Wait -PassThru
    if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
        throw 'Single-file Windows setup creation failed.'
    }
}
finally {
    foreach ($path in @($installerStageDirectory,$installerSedPath)) {
        if (Test-Path -LiteralPath $path) {
            $resolvedPath = (Resolve-Path -LiteralPath $path).Path
            $resolvedBuildParent = (Resolve-Path -LiteralPath (Split-Path -Parent $OutputDirectory)).Path
            if (-not $resolvedPath.StartsWith($resolvedBuildParent,[StringComparison]::OrdinalIgnoreCase)) {
                throw 'Refusing to remove one-file installer staging data outside the build directory.'
            }
            Remove-Item -LiteralPath $resolvedPath -Recurse -Force
        }
    }
}
Write-Host "Windows kiosk package created: $OutputDirectory"
Write-Host "Portable package archive created: $archivePath"
Write-Host "Single-file Windows setup created: $installerPath"
