#!/usr/bin/env bash
# doctor.sh -- 현재 셋업이 어디까지 됐고 무엇이 남았는지 진단합니다.
#
# 사용법:
#   ./doctor.sh           # 일반 진단 (Discord webhook 테스트 X)
#   ./doctor.sh --discord # Discord webhook 도 실제 테스트 메시지 전송

set -u

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

PASS=0
WARN=0
FAIL=0

ok()   { printf "  ${GREEN}[OK]${NC}    %s\n" "$1"; PASS=$((PASS+1)); }
warn() { printf "  ${YELLOW}[WARN]${NC}  %s\n" "$1"; WARN=$((WARN+1)); }
fail() { printf "  ${RED}[FAIL]${NC}  %s\n" "$1"; FAIL=$((FAIL+1)); }
section() { printf "\n${BOLD}%s${NC}\n" "$1"; }

# ~ 경로 expand
expand_tilde() {
    local p="$1"
    printf '%s' "${p/#\~/$HOME}"
}

printf "${BOLD}==================================================${NC}\n"
printf "${BOLD} OCI 자동 인스턴스 생성기 - 셋업 진단 (doctor)${NC}\n"
printf "${BOLD}==================================================${NC}\n"

# ---------- [1] oci.env ----------
section "[1] oci.env 파일"
if [ ! -f oci.env ]; then
    fail "oci.env 가 없습니다 -> 'cp oci.env.example oci.env' 실행"
    printf "\n결과: 통과 %d / 경고 %d / 실패 %d\n" "$PASS" "$WARN" "$FAIL"
    exit 1
fi
ok "oci.env 발견"

# 환경변수 로드 (export 모드)
# 따옴표 없는 공백 값(예: KEY=Foo Bar)이 있으면 bash 가 경고를 내지만,
# 다른 키들은 정상 로드되므로 stderr 만 숨긴다.
set -a
# shellcheck disable=SC1091
source oci.env 2>/dev/null
set +a

# ---------- [2] OCI_CONFIG ----------
section "[2] OCI_CONFIG (OCI API Config 파일)"
if [ -z "${OCI_CONFIG:-}" ]; then
    fail "OCI_CONFIG 가 비어있음"
elif [ "$OCI_CONFIG" = "/path/to/your/oci_config" ]; then
    fail "OCI_CONFIG 가 placeholder 값 그대로 -> oci.env 에서 실제 경로로 수정"
else
    OCI_CONFIG_EXPANDED=$(expand_tilde "$OCI_CONFIG")
    if [ ! -f "$OCI_CONFIG_EXPANDED" ]; then
        fail "OCI_CONFIG 파일 없음: $OCI_CONFIG_EXPANDED"
        echo "         -> STEP 1~2 따라 ~/.oci/config 파일 생성 필요"
    else
        ok "OCI_CONFIG 파일 존재: $OCI_CONFIG_EXPANDED"
        for key in user fingerprint tenancy region key_file; do
            if grep -qE "^${key}=" "$OCI_CONFIG_EXPANDED"; then
                ok "  - [DEFAULT] ${key}= 항목 있음"
            else
                fail "  - [DEFAULT] ${key}= 항목 누락"
            fi
        done
        # key_file 의 .pem 파일 실제 존재 여부
        KEY_FILE=$(grep -E "^key_file=" "$OCI_CONFIG_EXPANDED" | cut -d= -f2- | tr -d ' "' | head -1)
        if [ -n "$KEY_FILE" ]; then
            KEY_FILE_EXPANDED=$(expand_tilde "$KEY_FILE")
            if [ -f "$KEY_FILE_EXPANDED" ]; then
                ok "  - key_file 실제 존재: $KEY_FILE_EXPANDED"
            else
                fail "  - key_file 경로의 .pem 없음: $KEY_FILE_EXPANDED"
            fi
        fi
    fi
fi

# ---------- [3] OCT_FREE_AD ----------
section "[3] OCT_FREE_AD (가용 도메인)"
if [ -z "${OCT_FREE_AD:-}" ]; then
    warn "OCT_FREE_AD 가 비어있음 (대부분 AD-1)"
else
    ok "OCT_FREE_AD = $OCT_FREE_AD"
fi

# ---------- [4] SSH 공개키 ----------
section "[4] SSH_AUTHORIZED_KEYS_FILE"
if [ -z "${SSH_AUTHORIZED_KEYS_FILE:-}" ]; then
    fail "SSH_AUTHORIZED_KEYS_FILE 가 비어있음"
else
    SSH_PATH_EXPANDED=$(expand_tilde "$SSH_AUTHORIZED_KEYS_FILE")
    if [ -f "$SSH_PATH_EXPANDED" ]; then
        ok "SSH 공개키 존재: $SSH_PATH_EXPANDED"
    else
        warn "SSH 공개키 미존재: $SSH_PATH_EXPANDED"
        echo "         -> 첫 실행 시 자동 생성됨 (RSA 2048)"
    fi
fi

# ---------- [5] OCI_SUBNET_ID ----------
section "[5] OCI_SUBNET_ID"
if [ -z "${OCI_SUBNET_ID:-}" ]; then
    warn "OCI_SUBNET_ID 비어있음 (기존 VCN 자동 탐색 시도)"
    echo "         -> 신규 OCI 계정이면 STEP 3-1 따라 VCN/Subnet 생성 후 OCID 입력 필요"
else
    ok "OCI_SUBNET_ID = ${OCI_SUBNET_ID:0:60}..."
fi

# ---------- [6] Python venv + 패키지 ----------
section "[6] Python venv + 의존 패키지"
if [ ! -d .venv ]; then
    warn ".venv 없음 -> ./setup_init.sh 첫 실행 시 자동 생성됨"
elif [ ! -x .venv/bin/python ]; then
    fail ".venv/bin/python 없음 -> .venv 삭제 후 ./setup_init.sh 재실행"
else
    ok ".venv 존재"
    if .venv/bin/python -c "import oci, paramiko, dotenv, requests" 2>/dev/null; then
        ok "필수 패키지(oci, paramiko, dotenv, requests) 모두 설치됨"
    else
        fail "패키지 누락 -> '.venv/bin/pip install -r requirements.txt' 실행"
    fi
fi

# ---------- [7] OCI 인증 (read-only) ----------
section "[7] OCI 인증 (read-only API 호출)"
if [ ! -x .venv/bin/python ]; then
    warn "venv 미설치로 인증 검증 건너뜀"
elif [ -z "${OCI_CONFIG_EXPANDED:-}" ] || [ ! -f "${OCI_CONFIG_EXPANDED}" ]; then
    warn "OCI_CONFIG 미준비로 인증 검증 건너뜀"
else
    AUTH_RESULT=$(.venv/bin/python - <<PY 2>&1
import oci, sys
try:
    cfg = oci.config.from_file("$OCI_CONFIG_EXPANDED")
    iam = oci.identity.IdentityClient(cfg)
    user = iam.get_user(cfg["user"]).data
    print("OK:" + user.name)
except Exception as e:
    print("FAIL:" + type(e).__name__ + ": " + str(e))
PY
    )
    if [[ "$AUTH_RESULT" == OK:* ]]; then
        ok "OCI 인증 성공 -- 사용자: ${AUTH_RESULT#OK:}"
    else
        fail "OCI 인증 실패 -- ${AUTH_RESULT#FAIL:}"
    fi
fi

# ---------- [8] Discord ----------
section "[8] DISCORD_WEBHOOK (선택)"
if [ -z "${DISCORD_WEBHOOK:-}" ]; then
    warn "DISCORD_WEBHOOK 비어있음 (알림 없이 동작)"
elif [[ "${1:-}" == "--discord" ]]; then
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                 -H "Content-Type: application/json" -X POST \
                 -d '{"content":"[doctor.sh] webhook 테스트 메시지"}' \
                 "$DISCORD_WEBHOOK")
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
        ok "Discord webhook 정상 (테스트 메시지 1건 발송)"
    else
        fail "Discord webhook 응답 비정상: HTTP $HTTP_CODE"
    fi
else
    ok "DISCORD_WEBHOOK 설정됨 (실제 발송 테스트는 './doctor.sh --discord')"
fi

# ---------- 요약 ----------
printf "\n${BOLD}==================================================${NC}\n"
printf "${BOLD} 진단 결과: ${GREEN}통과 %d${NC} / ${YELLOW}경고 %d${NC} / ${RED}실패 %d${NC}\n" "$PASS" "$WARN" "$FAIL"
printf "${BOLD}==================================================${NC}\n"

if [ "$FAIL" -gt 0 ]; then
    printf "\n[FAIL] 항목들을 먼저 해결한 뒤 './setup_init.sh' 를 실행하세요.\n"
    exit 1
elif [ "$WARN" -gt 0 ]; then
    printf "\n실행 가능합니다. [WARN] 항목들은 선택 사항입니다.\n"
    printf "다음: ./setup_init.sh\n"
    exit 0
else
    printf "\n모든 셋업 완료! 다음: ./setup_init.sh\n"
    exit 0
fi
