#!/usr/bin/env bash

# 이전 실행에서 남은 로그 파일 정리
if ls *.log >/dev/null 2>&1; then
    rm -f *.log
    echo "[INFO] 이전 로그 파일을 삭제했습니다."
fi

# 비대화형 모드 (apt prompt 방지)
export DEBIAN_FRONTEND=noninteractive

# 사전 검증: oci.env 누락이 가장 흔한 셋업 실패 원인
if [ ! -f "oci.env" ]; then
    echo "[ERROR] oci.env 파일이 없습니다."
    echo "        1) cp oci.env.example oci.env"
    echo "        2) vi oci.env (또는 ./setup_env.sh 로 대화형 생성)"
    exit 1
fi

# 'rerun' 인자가 아니면 의존성 설치
if [ "$1" != "rerun" ]; then
    if type apt >/dev/null 2>&1; then
        sudo apt update -y
        sudo apt install python3-venv -y
    fi
    python3 -m venv .venv
fi

# 가상환경 활성화
if [ ! -f ".venv/bin/activate" ]; then
    echo "[ERROR] .venv 가 없습니다. 'rerun' 없이 다시 실행해 주세요: ./setup_init.sh"
    exit 1
fi
source .venv/bin/activate

# pip + 패키지 설치
if [ "$1" != "rerun" ]; then
    pip install --upgrade pip
    pip install wheel setuptools
    pip install -r requirements.txt
fi

# Discord 메시지 전송
send_discord_message() {
    curl -s -H "Content-Type: application/json" -X POST \
         -d "{\"content\":\"$1\"}" "$DISCORD_WEBHOOK" >/dev/null
}

# Telegram 메시지 전송
send_telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
         -d chat_id="$TELEGRAM_USER_ID" \
         -d text="$1" >/dev/null
}

# 통합 알림 인터페이스 (설정된 채널만 사용)
send_notification() {
    if [ -n "$DISCORD_WEBHOOK" ]; then
        send_discord_message "$1"
    fi

    if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_USER_ID" ]; then
        send_telegram_message "$1"
    fi
}

# 스크립트 종료 시 알림
trap 'send_notification "[알림] setup_init.sh 가 종료되었습니다."' EXIT

# 환경변수 로드 (export 없이 선언된 값도 자식 프로세스에 전달)
set -a
source oci.env
set +a

# 인터럽트(Ctrl+C / kill) 처리
cleanup() {
    send_notification "[중단] OCI 인스턴스 생성 스크립트가 중단되었습니다."
    if [ -n "$SCRIPT_PID" ]; then
        kill "$SCRIPT_PID" 2>/dev/null
    fi
    exit 0
}

# 일시정지(Ctrl+Z) 처리
handle_suspend() {
    send_notification "[일시정지] OCI 인스턴스 생성 스크립트가 일시정지되었습니다."
    if [ -n "$SCRIPT_PID" ]; then
        kill -STOP "$SCRIPT_PID" 2>/dev/null
    fi
    kill -STOP $$
}

trap cleanup SIGINT SIGTERM
trap handle_suspend SIGTSTP

# Python 메인 스크립트 백그라운드 실행 (stderr 까지 setup_init.log 에 캡처)
nohup python3 main.py > setup_init.log 2>&1 &
SCRIPT_PID=$!
echo "[INFO] main.py 실행 시작 (PID: $SCRIPT_PID)"

# 백그라운드 프로세스 생존 확인
is_script_running() {
    ps -p "$SCRIPT_PID" > /dev/null
}

# main.py 가 초기 검증 + OCI 클라이언트 초기화를 마치도록 잠시 대기
sleep 10

# 셋업 결과 판정
if [ -s "ERROR_IN_CONFIG.log" ]; then
    echo "[ERROR] 설정 오류가 발생했습니다. ERROR_IN_CONFIG.log 를 확인하고 수정 후 재실행하세요."
    echo "----- ERROR_IN_CONFIG.log -----"
    cat ERROR_IN_CONFIG.log
    echo "-------------------------------"
    send_notification "[설정 오류] ERROR_IN_CONFIG.log 를 확인하세요."
    exit 1
elif [ -s "INSTANCE_CREATED" ]; then
    echo "[성공] 인스턴스가 생성되었거나 이미 Free Tier 한도에 도달했습니다. INSTANCE_CREATED 파일을 확인하세요."
    send_notification "[성공] 인스턴스 생성 또는 Free Tier 한도 도달. INSTANCE_CREATED 확인 요망."
elif [ -s "launch_instance.log" ]; then
    echo "[INFO] 스크립트가 정상적으로 재시도 중입니다."
    send_notification "[진행 중] 인스턴스 생성 재시도가 진행 중입니다."
else
    echo "[INFO] 로그가 아직 생성되지 않았습니다. 60초 후 재확인합니다."
    sleep 60
    if [ -s "ERROR_IN_CONFIG.log" ]; then
        echo "[ERROR] 설정 오류 발생. ERROR_IN_CONFIG.log 확인 필요."
        cat ERROR_IN_CONFIG.log
        send_notification "[설정 오류] ERROR_IN_CONFIG.log 를 확인하세요."
        exit 1
    elif [ -s "launch_instance.log" ]; then
        echo "[INFO] 약간의 지연 후 정상 실행을 확인했습니다."
        send_notification "[진행 중] 짧은 지연 후 정상 실행을 확인했습니다."
    else
        echo "[ERROR] 처리되지 않은 예외가 발생했을 수 있습니다. setup_init.log 를 확인하세요."
        send_notification "[알 수 없는 오류] setup_init.log 를 확인해 주세요."
    fi
fi

# 백그라운드 프로세스가 종료될 때까지 모니터링
while is_script_running; do
    sleep 60
done

send_notification "[종료] OCI 인스턴스 생성 스크립트가 종료되었습니다."

deactivate
exit 0
