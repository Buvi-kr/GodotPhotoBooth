$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$output = Join-Path $here '..\bin\camera-bridge'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw 'Windows .NET Framework C# compiler is missing.' }
New-Item -ItemType Directory -Force -Path $output | Out-Null
$exePath = Join-Path $output 'CameraBridge.exe'
$sourcePath = Join-Path $here 'Program.cs'
& $compiler /nologo /target:winexe /optimize+ ("/out:$exePath") /reference:System.Windows.Forms.dll /reference:System.Drawing.dll $sourcePath
if ($LASTEXITCODE -ne 0) { throw "Camera bridge compile failed with exit code $LASTEXITCODE" }
Write-Host "Built standalone bridge at $output\CameraBridge.exe (Windows inbox .NET Framework required)."
