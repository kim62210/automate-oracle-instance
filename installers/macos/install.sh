#!/usr/bin/env bash
# install.sh -- OCI Free Tier ARM 인스턴스 자동 생성기 macOS 부트스트랩
#
# 동작:
#   1) 의존성 확인 (git, python3) -- 없으면 Homebrew 로 자동 설치 (Homebrew 자체는 자동 설치 X, 안내만)
#   2) 레포 git clone (or git pull)
#   3) ./setup.sh 인터랙티브 실행
#   4) ./setup_init.sh 실행
#
# 사용 방법:
#   - 더블클릭: 같은 디렉토리의 OciFreeArm.command
#   - 터미널 직접:  bash install.sh
#   - 원격 실행 (one-liner):
#       curl -fsSL https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/macos/install.sh | bash

set -euo pipefail

GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
RED=$'\033[0;31m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

ok()      { printf "  ${GREEN}[OK]${NC}    %s\n" "$1"; }
warn()    { printf "  ${YELLOW}[WARN]${NC}  %s\n" "$1"; }
fail()    { printf "  ${RED}[FAIL]${NC}  %s\n" "$1" >&2; }
section() { printf "\n${BOLD}${CYAN}[INSTALLER] %s${NC}\n" "$1"; }

pause_exit() {
    local code="${1:-0}"
    printf "\n"
    if [ -t 0 ]; then
        # shellcheck disable=SC2034
        read -r -p "Enter 를 눌러 종료" _ || true
    fi
    exit "$code"
}

REPO="https://github.com/kim62210/automate-oracle-instance.git"
TARGET="$HOME/automate-oracle-instance"

cat <<BANNER
============================================================
 OCI Free Tier ARM 인스턴스 자동 생성기 - macOS 설치
============================================================
BANNER

# ---------------- 의존성 ----------------
section "의존성 확인"

NEED_GIT=0
NEED_PY=0
command -v git >/dev/null 2>&1 || NEED_GIT=1
command -v python3 >/dev/null 2>&1 || NEED_PY=1

if [ "$NEED_GIT" -eq 1 ] || [ "$NEED_PY" -eq 1 ]; then
    if ! command -v brew >/dev/null 2>&1; then
        fail "Homebrew 가 없어 의존성을 자동 설치할 수 없습니다."
        echo
        echo "  Homebrew 설치 (한 번만, 약 5분):"
        echo "    /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        echo
        echo "  설치 후 이 스크립트를 다시 실행하세요."
        pause_exit 1
    fi
    [ "$NEED_GIT" -eq 1 ] && { echo "  -> brew install git"; brew install git; }
    [ "$NEED_PY" -eq 1 ] && { echo "  -> brew install python@3.12"; brew install python@3.12; }
fi
ok "git: $(command -v git)"
ok "python3: $(command -v python3)"

# ---------------- 레포 ----------------
section "레포 받기"
if [ -d "$TARGET/.git" ]; then
    echo "  -> 기존 레포 갱신: $TARGET"
    git -C "$TARGET" pull --ff-only origin main || true
else
    echo "  -> 새로 clone: $TARGET"
    git clone "$REPO" "$TARGET"
fi
chmod +x "$TARGET"/setup.sh "$TARGET"/setup_init.sh "$TARGET"/stop.sh "$TARGET"/doctor.sh "$TARGET"/setup_env.sh 2>/dev/null || true
ok "레포 준비: $TARGET"

# ---------------- setup.sh ----------------
section "OOBE 마법사 실행"
echo "  -> 4-입력 마법사가 시작됩니다."
echo

cd "$TARGET"
if ! ./setup.sh; then
    setup_exit=$?
    fail "setup.sh 비정상 종료 (exit $setup_exit)."
    echo "  레포 위치: $TARGET"
    echo "  직접 다시 실행: cd \"$TARGET\" && ./setup.sh"
    pause_exit "$setup_exit"
fi

# ---------------- setup_init.sh ----------------
section "인스턴스 자동 생성 시작"
if ! ./setup_init.sh; then
    init_exit=$?
    fail "setup_init.sh 비정상 종료 (exit $init_exit)."
    pause_exit "$init_exit"
fi

cat <<DONE

${BOLD}${GREEN}백그라운드에서 인스턴스 생성을 계속 시도합니다.${NC}

다음 명령으로 상태 확인 / 중지 가능:
  cd "$TARGET"
  ./doctor.sh        # 셋업 진단
  ./stop.sh          # 백그라운드 종료
  cat INSTANCE_CREATED   # 생성된 인스턴스 정보 (공용 IP)

DONE

pause_exit 0
