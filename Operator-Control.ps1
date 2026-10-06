$ErrorActionPreference = 'Stop'
$operationsDirectory = $PSScriptRoot
if ((Split-Path -Leaf $PSScriptRoot) -eq 'Operations') {
    $boothDirectory = Split-Path -Parent $PSScriptRoot
    $buildScript = Join-Path $boothDirectory 'Build-Windows.ps1'
    if (-not (Test-Path -LiteralPath $buildScript)) { $buildScript = $null }
} else {
    $boothDirectory = Join-Path $PSScriptRoot 'Build\Windows'
    $buildScript = Join-Path $PSScriptRoot 'Build-Windows.ps1'
}
$boothExe = Join-Path $boothDirectory 'ArtValleyPhotoBooth.exe'
$bridgeExe = Join-Path $boothDirectory 'CameraBridge\CameraBridge.exe'
$tunnelExe = Join-Path $boothDirectory 'StreamingAssets\cloudflared.exe'
$configPath = Join-Path $boothDirectory 'StreamingAssets\config.json'
$photosPath = Join-Path $boothDirectory 'MyPhotoBooth'
$logPath = Join-Path $boothDirectory 'CameraBridge\camera_bridge.log'

function Get-ManagedProcesses([string]$path) {

    @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $path })
}

function Show-Status {
    try { Clear-Host } catch { }
    Write-Host 'Art Valley Photo Booth · 관제 상태' -ForegroundColor Cyan
    Write-Host ''
    $booth = Get-ManagedProcesses $boothExe
    $bridge = Get-ManagedProcesses $bridgeExe
    $tunnel = Get-ManagedProcesses $tunnelExe
    Write-Host ("앱:       {0}" -f $(if ($booth.Count) { '실행 중' } else { '중지' }))
    Write-Host ("카메라:   {0}" -f $(if ($bridge.Count) { '브리지 실행 중' } else { '브리지 중지' }))
    Write-Host ("공유터널: {0}" -f $(if ($tunnel.Count) { '실행 중' } else { '중지' }))
    Write-Host ("카메라 포트 49152: {0}" -f $(if ((Test-NetConnection 127.0.0.1 -Port 49152 -InformationLevel Quiet -WarningAction SilentlyContinue)) { '연결됨' } else { '대기/끊김' }))
    Write-Host ''
    if (Test-Path -LiteralPath $configPath) {
        try {
            $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
            Write-Host ("카메라 요청: {0}×{1} @ {2} fps · 기본 장치={3} · 장치명='{4}'" -f $config.camera.requestedWidth, $config.camera.requestedHeight, $config.camera.requestedFPS, $config.camera.useDefaultDevice, $config.camera.deviceName)
            Write-Host ("크로마 키: {0} · 민감도 {1}% · 부드러움 {2}% · 반사 제거 {3}%" -f $config.global.targetColor, $config.global.masterSensitivity, $config.global.masterSmoothness, $config.global.masterSpillRemoval)
            Write-Host ("배경 프리셋: {0}개" -f $config.backgrounds.Count)
        } catch { Write-Host '설정 읽기 실패: config.json을 확인하세요.' -ForegroundColor Yellow }
    } else { Write-Host '설정 파일이 없습니다.' -ForegroundColor Yellow }
    if (Get-PnpDevice -Class Camera -PresentOnly -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK') {
        Write-Host 'Windows 카메라 장치: 사용 가능' -ForegroundColor Green
    } else { Write-Host 'Windows 카메라 장치: 감지 안 됨/권한 제한' -ForegroundColor Yellow }
    Write-Host ''
    if (Test-Path -LiteralPath $logPath) {
        Write-Host '최근 카메라 로그:' -ForegroundColor Cyan
        Get-Content -LiteralPath $logPath -Tail 8
    }
    Write-Host ''
}

while ($true) {
    Show-Status
    $buildLabel = if ($buildScript) { 'Windows 패키지 다시 빌드' } else { '재빌드 (개발 프로젝트에서만 가능)' }
    Write-Host '[1] 포토부스 실행  [2] 앱/브리지/터널 종료  [3] 설정 열기'
    Write-Host ("[4] 사진 폴더  [5] 배포 폴더  [6] 카메라 로그  [7] {0}" -f $buildLabel)
    Write-Host '[8] 진행/검수 문서 열기  [Q] 닫기'
    $selection = Read-Host '선택'
    if ($null -eq $selection) { break }
    $choice = $selection.Trim().ToUpperInvariant()
    switch ($choice) {
        '1' {
            if (-not (Test-Path -LiteralPath $boothExe)) { Write-Host '패키지가 없습니다. [7]로 먼저 빌드하세요.' -ForegroundColor Yellow; Start-Sleep -Seconds 2; continue }
            if (-not (Get-ManagedProcesses $boothExe).Count) { Start-Process -FilePath $boothExe | Out-Null }
        }
        '2' {
            foreach ($path in @($boothExe, $bridgeExe, $tunnelExe)) {
                Get-ManagedProcesses $path | Stop-Process -Force -ErrorAction SilentlyContinue
            }
            Start-Sleep -Milliseconds 400
        }
        '3' {
            if (Test-Path -LiteralPath $configPath) { Start-Process notepad.exe -ArgumentList @($configPath) | Out-Null }
            else { Write-Host '설정 파일이 없습니다.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
        '4' { New-Item -ItemType Directory -Force -Path $photosPath | Out-Null; Start-Process explorer.exe -ArgumentList @($photosPath) | Out-Null }
        '5' { Start-Process explorer.exe -ArgumentList @($boothDirectory) | Out-Null }
        '6' {
            if (Test-Path -LiteralPath $logPath) { Start-Process notepad.exe -ArgumentList @($logPath) | Out-Null }
            else { Write-Host '아직 카메라 로그가 없습니다. 앱을 실행하면 생성됩니다.' -ForegroundColor Yellow; Start-Sleep -Seconds 1 }
        }
        '7' {
            if ($buildScript -and (Test-Path -LiteralPath $buildScript)) {
                & $buildScript
                Read-Host '빌드 완료. Enter를 누르면 관제로 돌아갑니다' | Out-Null
            } else { Write-Host '이 포터블 배포본에는 Godot 원본/빌드 도구가 없습니다. 개발 프로젝트에서 재빌드하세요.' -ForegroundColor Yellow; Start-Sleep -Seconds 2 }
        }
        '8' { Start-Process notepad.exe -ArgumentList @((Join-Path $operationsDirectory 'OPERATOR_DASHBOARD.md')) | Out-Null }
        'Q' { break }
        default { }
    }
    if ($choice -eq 'Q') { break }
}
