#!/usr/bin/env bash

# OCI 환경설정 파일(oci.env)을 대화형으로 생성합니다.

ask() {
    # ask "질문" "기본값"
    local prompt="$1"
    local default="$2"
    local answer
    if [ -n "$default" ]; then
        read -p "$prompt [기본값: $default]: " answer
        echo "${answer:-$default}"
    else
        read -p "$prompt: " answer
        echo "$answer"
    fi
}

ask_yn() {
    # ask_yn "질문" "y|n"
    local prompt="$1"
    local default="$2"
    local answer
    while true; do
        read -p "$prompt (y/n) [기본값: $default]: " answer
        answer="${answer:-$default}"
        case "${answer,,}" in
            y) echo "True"; return ;;
            n) echo "False"; return ;;
            *) echo "  → y 또는 n 으로 답해 주세요." ;;
        esac
    done
}

clear
cat <<'EOF'
============================================================
 OCI 인스턴스 자동 생성 - 환경설정 마법사
 모르는 항목은 Enter 로 기본값을 사용해도 됩니다.
============================================================
EOF
echo

OCI_CONFIG=$(ask "OCI Config 파일 절대 경로" "$HOME/.oci/config")

INSTANCE_NAME=$(ask "인스턴스 표시 이름" "a1-free-arm")

echo
echo "셰이프를 선택하세요:"
echo "  1) VM.Standard.A1.Flex   (ARM, 4 OCPU / 24GB RAM, 권장)"
echo "  2) VM.Standard.E2.1.Micro (AMD, 1 OCPU / 1GB RAM)"
while true; do
    read -p "선택 (1 또는 2) [기본값: 1]: " SHAPE_CHOICE
    SHAPE_CHOICE="${SHAPE_CHOICE:-1}"
    case "$SHAPE_CHOICE" in
        1) SHAPE="VM.Standard.A1.Flex"; break ;;
        2) SHAPE="VM.Standard.E2.1.Micro"; break ;;
        *) echo "  → 1 또는 2 를 입력하세요." ;;
    esac
done

SECOND_MICRO=$(ask_yn "두 번째 Free Tier Micro 인스턴스를 만드시나요?" "n")

REGIONS=$(ask "시도할 리전 (쉼표 구분)" "ap-seoul-1,ap-chuncheon-1")

SSH_KEY=$(ask "SSH 공개키(.pub) 절대 경로 (없으면 자동 생성됨)" "$HOME/.ssh/id_ed25519_oci.pub")

SUBNET_ID=$(ask "서브넷 OCID (로컬 실행 시 필수, 인스턴스 안에서면 비워둠)" "")

IMAGE_ID=$(ask "이미지 OCID (비우면 OS/버전으로 자동 탐색)" "")

ASSIGN_PUBLIC_IP=$(ask_yn "공용 IP 를 자동 할당할까요?" "y")
ASSIGN_PUBLIC_IP="${ASSIGN_PUBLIC_IP,,}"   # True/False -> true/false

DISCORD_WEBHOOK=$(ask "Discord Webhook URL (선택, 비워도 됨)" "")

# 기존 oci.env 백업
if [ -f oci.env ]; then
    mv oci.env oci.env.bak
    echo "[INFO] 기존 oci.env 를 oci.env.bak 으로 백업했습니다."
fi

cat > oci.env <<EOF
# 자동 생성됨: $(date '+%Y-%m-%d %H:%M:%S')
OCI_CONFIG=$OCI_CONFIG
OCT_FREE_AD=AD-1
OCI_REGIONS=$REGIONS
DISPLAY_NAME=$INSTANCE_NAME
OCI_COMPUTE_SHAPE=$SHAPE
SECOND_MICRO_INSTANCE=$SECOND_MICRO
REQUEST_WAIT_TIME_SECS=60
SSH_AUTHORIZED_KEYS_FILE=$SSH_KEY
OCI_SUBNET_ID=$SUBNET_ID
OCI_IMAGE_ID=$IMAGE_ID
OPERATING_SYSTEM=Canonical Ubuntu
OS_VERSION=24.04
ASSIGN_PUBLIC_IP=$ASSIGN_PUBLIC_IP
BOOT_VOLUME_SIZE=50

# Discord Webhook (비워두면 알림 없음)
DISCORD_WEBHOOK=$DISCORD_WEBHOOK
EOF

echo
echo "[OK] oci.env 가 생성되었습니다."
echo "     이어서 './setup_init.sh' 를 실행해 인스턴스 생성을 시작하세요."
