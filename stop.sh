#!/usr/bin/env bash
# stop.sh -- 백그라운드에서 도는 main.py 를 안전하게 종료합니다.
#
# 우선순위:
#   1) .main.pid 파일이 있으면 그 PID 사용
#   2) 없으면 pgrep 으로 'python3 main.py' 검색
#
# SIGTERM 전송 후 5초 대기, 그래도 살아있으면 SIGKILL.

set -u

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()    { printf "  ${GREEN}[OK]${NC}    %s\n" "$1"; }
warn()  { printf "  ${YELLOW}[WARN]${NC}  %s\n" "$1"; }
fail()  { printf "  ${RED}[FAIL]${NC}  %s\n" "$1" >&2; }

cd "$(dirname "$0")"

PID_FILE=".main.pid"
PIDS=()

if [ -f "$PID_FILE" ]; then
    P=$(tr -d '[:space:]' < "$PID_FILE")
    if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
        PIDS+=("$P")
    else
        warn "PID 파일이 가리키는 프로세스(${P:-empty}) 가 이미 종료됨 → 파일 정리"
        rm -f "$PID_FILE"
    fi
fi

if [ ${#PIDS[@]} -eq 0 ]; then
    while IFS= read -r p; do
        [ -n "$p" ] && PIDS+=("$p")
    done < <(pgrep -f 'python3 main.py' 2>/dev/null || true)
fi

if [ ${#PIDS[@]} -eq 0 ]; then
    warn "실행 중인 main.py 프로세스가 없습니다."
    exit 0
fi

for pid in "${PIDS[@]}"; do
    if kill "$pid" 2>/dev/null; then
        ok "PID $pid → SIGTERM 전송"
    else
        fail "PID $pid → SIGTERM 전송 실패"
    fi
done

# graceful 종료 대기
SECONDS_WAITED=0
while [ "$SECONDS_WAITED" -lt 5 ]; do
    ALIVE=0
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            ALIVE=1
            break
        fi
    done
    [ "$ALIVE" -eq 0 ] && break
    sleep 1
    SECONDS_WAITED=$((SECONDS_WAITED + 1))
done

# 남은 프로세스 강제 종료
for pid in "${PIDS[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
        if kill -9 "$pid" 2>/dev/null; then
            warn "PID $pid → SIGKILL (5초 내 종료 안 됨)"
        else
            fail "PID $pid → SIGKILL 실패"
        fi
    fi
done

rm -f "$PID_FILE"
ok "정상 종료 완료"
