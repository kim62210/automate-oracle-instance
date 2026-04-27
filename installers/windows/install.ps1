# install.ps1 -- OCI Free Tier ARM 인스턴스 자동 생성기 Windows 부트스트랩
#
# 동작:
#   1) WSL 설치 여부 확인 (없으면 안내 메시지 후 종료, 자동 install 안 함)
#   2) 디폴트 WSL 배포판 확인
#   3) WSL 안에서 의존성(git, python3, python3-venv) 자동 설치
#   4) 레포 git clone (or git pull)
#   5) ./setup.sh 인터랙티브 실행
#   6) ./setup_init.sh 실행
#
# 사용 방법:
#   - 더블클릭: 같은 디렉토리의 OciFreeArm.cmd
#   - PowerShell 직접:  powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
#   - 원격 실행 (one-liner):
#       iwr -useb https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/windows/install.ps1 | iex

$ErrorActionPreference = "Stop"
try { $Host.UI.RawUI.WindowTitle = "OCI Free Tier Installer" } catch {}

function Write-Section { param($Text)
    Write-Host ""
    Write-Host "[INSTALLER] $Text" -ForegroundColor Cyan
}
function Write-Ok   { param($Text) Write-Host "  [OK]   $Text" -ForegroundColor Green }
function Write-Warn { param($Text) Write-Host "  [WARN] $Text" -ForegroundColor Yellow }
function Write-Fail { param($Text) Write-Host "  [FAIL] $Text" -ForegroundColor Red }

function Pause-Exit { param($Code = 0)
    Write-Host ""
    try { Read-Host "Enter 를 눌러 종료" | Out-Null } catch {}
    exit $Code
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " OCI Free Tier ARM 인스턴스 자동 생성기 - Windows 설치" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ---------------- WSL 확인 ----------------
Write-Section "WSL 확인"

$wslCmd = Get-Command wsl.exe -ErrorAction SilentlyContinue
if (-not $wslCmd) {
    Write-Fail "WSL 이 설치되어 있지 않습니다."
    Write-Host ""
    Write-Host "설치 방법:" -ForegroundColor Yellow
    Write-Host "  1) PowerShell 을 '관리자 권한으로 실행'"
    Write-Host "  2) 다음 명령:  wsl --install"
    Write-Host "  3) 컴퓨터 재부팅"
    Write-Host "  4) 첫 로그인 시 사용자 이름/비밀번호 설정"
    Write-Host "  5) 이 스크립트를 다시 실행"
    Write-Host ""
    Write-Host "공식 가이드: https://learn.microsoft.com/ko-kr/windows/wsl/install" -ForegroundColor Blue
    Pause-Exit 1
}

# wsl --status 응답 확인
$null = & wsl.exe --status 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "WSL 명령은 있지만 정상 응답하지 않습니다 (커널/플랫폼 미준비 가능)."
    Write-Host "  해결: 관리자 PowerShell 에서 'wsl --install' 또는 'wsl --update' 실행 후 재부팅."
    Pause-Exit 1
}

# 디폴트 배포판 확인 (wsl 출력은 UTF-16 LE 라 NUL 바이트 정리 필요)
$distroLines = & wsl.exe -l -q 2>$null
$distros = @()
foreach ($line in $distroLines) {
    $clean = ($line -replace "`0", "").Trim()
    if ($clean -ne "") { $distros += $clean }
}
if ($distros.Count -eq 0) {
    Write-Fail "설치된 WSL 배포판이 없습니다."
    Write-Host "  해결: 관리자 PowerShell 에서 'wsl --install -d Ubuntu' 실행, 첫 로그인 사용자/비밀번호 설정 후 재실행."
    Pause-Exit 1
}
$distro = $distros[0]
Write-Ok "WSL 디폴트 배포판: $distro"

# ---------------- 의존성 + 레포 준비 (배치) ----------------
Write-Section "의존성 설치 + 레포 받기 (WSL: $distro)"
Write-Host "  -> 첫 실행 시 'sudo' 비밀번호 입력 프롬프트가 나타날 수 있습니다."

$prepScript = @'
set -e
REPO="https://github.com/kim62210/automate-oracle-instance.git"
TARGET="$HOME/automate-oracle-instance"

NEED=0
for cmd in git python3; do command -v "$cmd" >/dev/null 2>&1 || NEED=1; done
python3 -c "import venv" >/dev/null 2>&1 || NEED=1
if [ "$NEED" -eq 1 ]; then
    echo "  -> apt 로 git/python3/python3-venv 설치 (sudo 비밀번호 필요)"
    sudo apt update -y
    sudo apt install -y git python3 python3-venv
fi

if [ -d "$TARGET/.git" ]; then
    echo "  -> 기존 레포 갱신: $TARGET"
    git -C "$TARGET" pull --ff-only origin main || true
else
    echo "  -> 새로 clone: $TARGET"
    git clone "$REPO" "$TARGET"
fi

cd "$TARGET"
chmod +x setup.sh setup_init.sh stop.sh doctor.sh setup_env.sh 2>/dev/null || true
echo "[OK] 레포 준비: $TARGET"
'@

# WSL 안 /tmp 에 스크립트 작성 후 bash 로 실행
$prepScript | & wsl.exe -d $distro -e bash -lc "cat > /tmp/oci-prep.sh && bash /tmp/oci-prep.sh"
if ($LASTEXITCODE -ne 0) {
    Write-Fail "의존성/레포 준비 실패 (exit $LASTEXITCODE)."
    Pause-Exit 1
}

# ---------------- OOBE setup.sh (인터랙티브) ----------------
Write-Section "OOBE 마법사 실행"
Write-Host "  -> 4-입력 마법사가 시작됩니다. 안내에 따라 진행하세요."
Write-Host ""

& wsl.exe -d $distro --cd "~/automate-oracle-instance" -e bash -lc "./setup.sh"
$setupExit = $LASTEXITCODE

if ($setupExit -ne 0) {
    Write-Fail "setup.sh 비정상 종료 (exit $setupExit)."
    Write-Host ""
    Write-Host "WSL 콘솔에서 직접 다시 실행해 보세요:"
    Write-Host "  wsl -d $distro --cd ~/automate-oracle-instance -e bash -lc './setup.sh'" -ForegroundColor Cyan
    Pause-Exit $setupExit
}

# ---------------- setup_init.sh (자동 생성 시작) ----------------
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " 셋업 완료 — 인스턴스 자동 생성을 시작합니다" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""

& wsl.exe -d $distro --cd "~/automate-oracle-instance" -e bash -lc "./setup_init.sh"
$initExit = $LASTEXITCODE

Write-Host ""
if ($initExit -eq 0) {
    Write-Host "백그라운드에서 인스턴스 생성을 계속 시도합니다." -ForegroundColor Cyan
    Write-Host "다음 명령으로 상태 확인 / 중지 가능 (WSL 콘솔):"
    Write-Host "  cd ~/automate-oracle-instance" -ForegroundColor Cyan
    Write-Host "  ./doctor.sh        # 셋업 진단" -ForegroundColor Cyan
    Write-Host "  ./stop.sh          # 백그라운드 종료" -ForegroundColor Cyan
    Write-Host "  cat INSTANCE_CREATED   # 생성된 인스턴스 정보" -ForegroundColor Cyan
} else {
    Write-Fail "setup_init.sh 비정상 종료 (exit $initExit)."
}
Pause-Exit $initExit
