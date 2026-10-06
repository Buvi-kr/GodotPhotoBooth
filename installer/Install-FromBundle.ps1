$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms

function Show-InstallMessage([string]$message, [System.Windows.Forms.MessageBoxIcon]$icon) {
    [System.Windows.Forms.MessageBox]::Show($message, 'Art Valley Photo Booth', [System.Windows.Forms.MessageBoxButtons]::OK, $icon) | Out-Null
}

try {
    $bundlePath = Join-Path $PSScriptRoot 'ArtValleyPhotoBooth-Windows.zip'
    $installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Art Valley Photo Booth'
    $applicationPath = Join-Path $installDirectory 'ArtValleyPhotoBooth.exe'
    if (-not (Test-Path -LiteralPath $bundlePath -PathType Leaf)) {
        throw 'The photo booth package is missing from this setup file.'
    }
    if ((Get-Process -Name 'ArtValleyPhotoBooth' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $applicationPath }).Count -gt 0) {
        throw 'The photo booth is running. Close it and run setup again.'
    }

    New-Item -ItemType Directory -Force -Path $installDirectory | Out-Null
    Expand-Archive -LiteralPath $bundlePath -DestinationPath $installDirectory -Force
    if (-not (Test-Path -LiteralPath $applicationPath -PathType Leaf)) {
        throw 'Setup finished without finding the photo booth application.'
    }

    $programsDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    New-Item -ItemType Directory -Force -Path $programsDirectory | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut((Join-Path $programsDirectory 'Art Valley Photo Booth.lnk'))
    $shortcut.TargetPath = $applicationPath
    $shortcut.WorkingDirectory = $installDirectory
    $shortcut.Description = 'Art Valley Photo Booth'
    $shortcut.Save()

    $startupDirectory = [Environment]::GetFolderPath('Startup')
    New-Item -ItemType Directory -Force -Path $startupDirectory | Out-Null
    $startupShortcut = $shell.CreateShortcut((Join-Path $startupDirectory 'Art Valley Photo Booth.lnk'))
    $startupShortcut.TargetPath = $applicationPath
    $startupShortcut.WorkingDirectory = $installDirectory
    $startupShortcut.Description = 'Start Art Valley Photo Booth when this Windows account signs in'
    $startupShortcut.Save()

    Start-Process -FilePath $applicationPath -WorkingDirectory $installDirectory
} catch {
    Show-InstallMessage $_.Exception.Message ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
