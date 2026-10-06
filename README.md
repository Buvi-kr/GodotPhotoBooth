# GodotPhotoBooth

포천아트밸리 천문과학관 Unity 포토부스를 Godot 4.7.2로 옮기는 Windows 키오스크 프로젝트입니다. Unity 원본은 이 저장소의 상위 `Assets/`에 남아 있으며, Godot 이식본은 이 디렉터리에서 개발합니다.

> **운영 검수 전 상태:** 앱과 Windows 패키지는 빌드되지만 예정된 Insta360 카메라 실측, 실제 인물·조명 크로마 품질, 원본 Unity와 전체 화면 대조를 마치지 않았습니다. 현재 노트북 카메라는 1920×1080/30 요청에 1280×720 MJPEG로 협상했고, 고유 프레임은 약 2.7–3.4fps였습니다. 이 수치는 현장 사용에 충분하다고 볼 수 없습니다.

## 기능과 흐름

대기 → 배경 선택 → 촬영 시작과 8초 카운트다운 → 합성 사진 저장 → 결과/QR → 재촬영 또는 처음으로 돌아가는 흐름을 구현합니다. 대기 복귀 시간은 Unity 활성 씬 설정인 60초를 따릅니다.

- 전역·배경별 크로마키, 배경 변환, 색 보정, crop/fade 설정을 JSON에서 읽고 관리자 화면에서 편집합니다.
- 마스터 키 색은 원본 현장 설정인 `#D5DBE0`를 유지합니다. 관리자 모드는 Ctrl+Alt+S, 설정 새로 읽기는 F5입니다.
- Windows 카메라 입력은 VFW 브리지가 담당합니다. MJPEG는 압축 상태로 로컬 TCP를 건너 Godot이 JPEG를 풀고, BI_RGB 24-bit 입력은 브리지에서 RGB로 변환합니다.
- 요청 해상도는 640×480부터 3840×2160까지, 요청 FPS는 15/24/30/60에서 고릅니다. 실제 입력 해상도와 수신 FPS가 낮으면 관리자 화면에 장치 제한으로 표시합니다.
- 결과 JPG와 월별 CSV를 저장하고 로컬 HTTP 페이지, QR 이미지, Cloudflare quick tunnel로 휴대전화 공유를 제공합니다.
- 배경 6종과 전경·썸네일, 결과 배경, Ogg Theora 영상, Noto Sans KR을 포함합니다.

## 한 번에 실행·관제

프로젝트 또는 포터블 패키지에서 [Operator-Control.cmd](Operator-Control.cmd)를 실행합니다. 메뉴에서 앱 실행·종료, 프로세스/포트/설정/카메라 로그 확인, 설정 파일·사진·배포 폴더 열기, 개발 프로젝트 재빌드, 운영 문서 열기를 선택할 수 있습니다.

운영 방법과 실물 점검 순서는 [OPERATOR_DASHBOARD.md](OPERATOR_DASHBOARD.md)에 있습니다. 개발 진행 메모와 현장 시험 로그는 공개 저장소에서 제외합니다.

## 개발 요구 사항

- Windows 10/11, Godot 4.7.2 Windows x86_64, 해당 버전의 Windows export template
- 카메라를 쓰려면 Windows VFW 카메라 드라이버와 `CameraBridge/build.ps1`이 사용하는 .NET Framework C# 컴파일러
- 외부 QR 공유에는 인터넷 연결, `runtime/cloudflared.exe`, 쓰기 가능한 실행 폴더 필요

프로젝트를 Godot 편집기에서 열고 `Main.tscn`을 실행합니다. 카메라 브리지는 로컬에서 먼저 만듭니다.

```powershell
Set-Location 'C:\path\to\GodotPhotoBooth'
& .\CameraBridge\build.ps1
```

개발 실행과 패키지 빌드 모두 `runtime/cloudflared.exe`를 사용합니다. Godot 프로젝트 폴더만 복사하거나 별도 저장소로 옮겨도 Unity 폴더에 의존하지 않습니다.

## Windows 포터블 패키지 빌드

기본 명령은 프로젝트 내 로컬 Godot 도구와 export template을 사용합니다.

```powershell
& .\Build-Windows.ps1
```

Godot와 template을 다른 위치에 설치했다면 경로를 지정할 수 있습니다.

```powershell
& .\Build-Windows.ps1 `
  -Godot 'C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' `
  -ExportTemplate 'C:\Tools\Godot\windows_release_x86_64.exe'
```

완료되면 실행 파일은 `Build/Windows/`, 배포 압축은 `Build/ArtValleyPhotoBooth-Windows.zip`에 생성됩니다. ZIP 안의 `Operations/`에 관제 프로그램과 안내서가 들어갑니다. `Build/`, 엔진 다운로드 및 export template은 생성·로컬 도구이므로 Git에서 제외합니다.

실행 폴더에 쓰기 권한을 주세요. 설정은 `StreamingAssets/config.json`, 사진·CSV·터널 로그는 `MyPhotoBooth/`에 둡니다. 사진 자동 정리는 Unity와 같이 1일 경과분이 대상이고 최소 보관 수는 0입니다.

## 구조

```text
scripts/main.gd                  상태와 화면 전환 연결
scripts/booth_state_presenter.gd 상태별 UI 표시
scripts/photo_capture_flow.gd    카운트다운·화면 캡처·저장·결과 전환
scripts/camera_feed.gd           TCP 프레임 수신·JPEG 디코드·재연결
scripts/photo_sharing.gd         로컬 HTTP·QR·터널 생명주기
scripts/photo_library.gd         JPG·CSV·오래된 사진 정리
scripts/admin_settings_panel.gd  크로마·배경·카메라 관리자 UI
scripts/chroma_settings_applier.gd Unity JSON → 셰이더 설정 변환
CameraBridge/Program.cs          Windows VFW 장치·프레임 송신
runtime/cloudflared.exe          외부 QR 공유용 터널 실행 파일
shaders/chroma_key.gdshader      GPU 크로마·색 보정·crop/fade
```

## 확인 결과와 한계

- 상태 입력·촬영 수명주기·설정 변환의 합성 점검, QR/공유의 합성 이미지 통합 점검 기록이 있습니다. 현재 크로마 셰이더 합성 픽셀에서 설정 키 색은 투명, 대비색은 불투명으로 나왔습니다.
- Godot JPEG 프레임 디코드 경로, 노트북 카메라 연결, Windows 패키지 기동을 확인했습니다. 테스트 촬영본은 보관하지 않았습니다.
- 이전 14fps 수치는 중복 프레임 전송까지 새 프레임으로 세어 잘못 기록한 것입니다. 중복 전송을 제거해 재측정한 노트북 결과는 10초 27장(약 2.7fps), 패키지 앱 로그의 한 안정 구간은 3.4fps입니다.
- Insta360 웹캠 모드의 FHD/4K 지원 여부와 FPS는 아직 모릅니다. 관리자 화면에서 해상도를 요청하는 것만으로 실제 센서 출력이 바뀌는 것은 아닙니다.
- 실제 녹색 배경과 인물의 테두리·머리카락 품질, 휴대전화의 실제 QR 스캔, 장시간 성능, 현장 모니터에서 Unity와 동일한 화면인지 확인이 필요합니다.

## 데이터·네트워크

현재 QR 외부 공유는 Cloudflare Quick Tunnel을 사용합니다. 소프트웨어 자체는 Apache 2.0이며 현재 무료지만, Cloudflare는 Quick Tunnel을 테스트·개발용으로 분류하고 가동시간 SLA를 보장하지 않습니다. 과학관 상시 운영은 안정 주소의 관리형 터널(도메인이 필요할 수 있음) 또는 방문자 Wi-Fi 내 로컬 QR 중 하나로 전환해야 합니다. 기본 공개 터널에는 유료 Access 플랜이 필요하지 않다고 Cloudflare가 안내합니다. 또한 Quick Tunnel URL/사진 페이지에는 인증이 없으므로 링크 또는 QR을 가진 사람이 사진에 접근할 수 있습니다. 보안·보관·장애복구 점검은 [운영 대시보드](OPERATOR_DASHBOARD.md)를 따르세요.

## 라이선스

앱 소스와 프로젝트 문서는 [MIT License](LICENSE)를 적용합니다. Godot와 내부 제3자 라이브러리, cloudflared, Noto Sans KR은 각자 원래 라이선스를 유지하며 고지는 [LICENSES.md](LICENSES.md)와 `licenses/`에 포함됩니다. 박물관 상표·사진·배경·영상은 MIT 적용 대상이 아니며, GitHub 공개 전 해당 미디어 자산의 공개·배포 권한을 확인하세요.

## 공개 저장소와 과학관 설치본 구분

- GitHub에는 앱 코드와 라이선스 고지만 공개합니다. `.gitignore`가 박물관 배경·전경·썸네일·영상, 현장 설정, 실행 결과물, 로그, 사진·CSV, cloudflared 실행 파일을 제외합니다.
- `Build-Windows.ps1`로 만드는 Windows 키오스크 ZIP은 과학관 내부 설치용입니다. 화면에 배경과 영상을 표시해야 하므로 Godot 리소스가 실행 파일 안에 포함됩니다. 이 ZIP이나 실행 파일을 공개 GitHub 릴리스에 첨부하지 마세요.
- 공개 저장소만으로는 미디어와 `data/config.json`이 없어 완전한 앱을 빌드할 수 없습니다. 내부 승인된 배포 담당자가 원본 자산·설정·cloudflared를 로컬에 준비한 뒤 키오스크 패키지를 만듭니다.
- GitHub에 올리기 전 `git status --short --ignored`와 업로드 파일 목록에서 배경·영상·사진·CSV·로그·개인정보·실행 파일을 다시 확인하세요. 이미 추적되거나 스테이징된 파일은 `.gitignore`만으로 빠지지 않으니 공개 전에 인덱스도 확인해야 합니다.
