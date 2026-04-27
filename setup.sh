#!/usr/bin/env bash
# setup.sh -- 비개발자용 4-입력 OOBE 마법사.
#
# 동작:
#   [1] ~/Downloads 의 .pem 자동 감지 → ./oci_api_private_key.pem 이동
#   [2] "구성 파일 미리보기" 통째로 받아 ./oci_config 자동 생성
#       (key_file 라인 절대경로로 자동 치환)
#   [3] OCI 인증 검증 + AD 자동 탐지 + 공용 서브넷 자동 탐색
#       (없으면 Free Tier VCN 자동 생성 또는 OCID 직접 입력)
#   [4] Discord Webhook URL 입력 (선택)
# 결과: oci.env 자동 작성. 이어서 ./setup_init.sh 실행하면 됨.

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

ok()    { printf "  ${GREEN}[OK]${NC}    %s\n" "$1"; }
warn()  { printf "  ${YELLOW}[WARN]${NC}  %s\n" "$1"; }
fail()  { printf "  ${RED}[FAIL]${NC}  %s\n" "$1" >&2; exit 1; }
step()  { printf "\n${BOLD}%s${NC}\n" "$1"; }
ask()   {
    # ask "프롬프트" "기본값" → 결과는 stdout
    local prompt="$1"
    local default="${2:-}"
    local answer
    if [ -n "$default" ]; then
        read -r -p "  $prompt [기본값: $default]: " answer < /dev/tty
        printf '%s' "${answer:-$default}"
    else
        read -r -p "  $prompt: " answer < /dev/tty
        printf '%s' "$answer"
    fi
}

cd "$(dirname "$0")"

clear
cat <<'BANNER'
============================================================
 OCI Free Tier 인스턴스 OOBE 셋업 (비개발자용 4-입력)
============================================================
 진행 전 OCI Console 에서 다음을 준비해 두세요:
   1) API 키 추가 → 개인키(.pem) 다운로드  (브라우저)
   2) "구성 파일 미리보기" 박스 내용 클립보드 복사 (브라우저)
============================================================
BANNER

# ---------- [1/4] .pem 자동 감지 / 이동 ----------
step "[1/4] OCI API 키 (.pem) 배치"

DEFAULT_PEM=""
if compgen -G "$HOME/Downloads/*.pem" > /dev/null 2>&1; then
    # shellcheck disable=SC2012
    DEFAULT_PEM=$(ls -t "$HOME"/Downloads/*.pem 2>/dev/null | head -n 1)
fi

if [ -n "$DEFAULT_PEM" ]; then
    echo "  ~/Downloads 에서 가장 최근 .pem 자동 감지: $(basename "$DEFAULT_PEM")"
    PEM_INPUT=$(ask "Enter=그대로 사용 / 다른 파일이면 절대경로 입력" "$DEFAULT_PEM")
else
    PEM_INPUT=$(ask "다운받은 .pem 절대경로 입력 (예: ~/Downloads/oracle.pem)" "")
fi

# ~ 확장
PEM_INPUT="${PEM_INPUT/#\~/$HOME}"
[ -n "$PEM_INPUT" ] || fail ".pem 경로가 비어있습니다."
[ -f "$PEM_INPUT" ] || fail ".pem 파일을 찾을 수 없습니다: $PEM_INPUT"

cp -- "$PEM_INPUT" ./oci_api_private_key.pem
chmod 600 ./oci_api_private_key.pem
ok ".pem → ./oci_api_private_key.pem (chmod 600)"

# ---------- [2/4] oci_config 입력 ----------
step "[2/4] OCI Console '구성 파일 미리보기' 붙여넣기"
cat <<'HINT'
  → 박스 내용을 통째로 붙여넣고, 빈 줄에서 Ctrl+D 를 누르세요.
  → 예시 형태:
      [DEFAULT]
      user=ocid1.user.oc1..aaaa...
      fingerprint=xx:xx:...
      tenancy=ocid1.tenancy.oc1..aaaa...
      region=ap-seoul-1
      key_file=<path to your private keyfile> # TODO
HINT
echo

TMP_CFG=$(mktemp)
trap 'rm -f "$TMP_CFG" "$TMP_CFG.bak"' EXIT
cat > "$TMP_CFG" < /dev/tty

# 기본 검증
for k in user fingerprint tenancy region; do
    grep -qE "^${k}=" "$TMP_CFG" \
        || fail "구성 파일 미리보기에 '${k}=' 라인이 없습니다. 다시 시도해 주세요."
done

# key_file= 라인 자동 치환 (없으면 추가)
ABS_PEM="$(pwd)/oci_api_private_key.pem"
if grep -qE "^key_file=" "$TMP_CFG"; then
    # macOS / GNU sed 양쪽 호환을 위해 -i.bak 사용
    sed -i.bak -E "s|^key_file=.*|key_file=$ABS_PEM|" "$TMP_CFG"
    rm -f "$TMP_CFG.bak"
else
    printf '\nkey_file=%s\n' "$ABS_PEM" >> "$TMP_CFG"
fi

mv "$TMP_CFG" ./oci_config
trap - EXIT
ok "oci_config 생성됨 (key_file=$ABS_PEM 절대경로 치환)"

# ---------- venv 준비 (인증 검증용) ----------
step "[자동] Python 가상환경 준비"
if [ ! -d .venv ]; then
    python3 -m venv .venv
    .venv/bin/pip install --upgrade pip --quiet
    .venv/bin/pip install -r requirements.txt --quiet
    ok ".venv 생성 + 의존 패키지 설치"
else
    ok ".venv 이미 존재 (재사용)"
fi

# ---------- [자동] 인증 검증 + AD 자동 탐지 + 공용 서브넷 탐색 ----------
step "[자동] OCI 인증 / AD 탐지 / 공용 서브넷 탐색"

PROBE_RESULT=$(.venv/bin/python - <<'PY' 2>&1 || true
import json
import sys
import oci

cfg_path = "./oci_config"
out: dict = {}

try:
    cfg = oci.config.from_file(cfg_path)
    iam = oci.identity.IdentityClient(cfg)
    user = iam.get_user(cfg["user"]).data
    out["user"] = user.name

    ads = iam.list_availability_domains(cfg["tenancy"]).data
    short_ads = []
    for a in ads:
        for tok in a.name.split("-"):
            if tok.startswith("AD") and tok not in short_ads:
                short_ads.append(tok)
    out["ads"] = short_ads or ["AD-1"]

    vnet = oci.core.VirtualNetworkClient(cfg)
    subnets = vnet.list_subnets(cfg["tenancy"]).data
    public_subnets = [
        s for s in subnets
        if s.lifecycle_state == "AVAILABLE" and not s.prohibit_public_ip_on_vnic
    ]
    out["subnet_id"] = public_subnets[0].id if public_subnets else ""

    print(json.dumps(out))
except Exception as e:
    print(json.dumps({"error": f"{type(e).__name__}: {e}"}))
    sys.exit(0)
PY
)

if echo "$PROBE_RESULT" | grep -q '"error"'; then
    ERR_MSG=$(.venv/bin/python -c "import sys,json;print(json.loads(sys.stdin.read()).get('error','unknown'))" <<< "$PROBE_RESULT")
    fail "OCI 인증 실패: $ERR_MSG
        → oci_config 의 user/fingerprint/tenancy/region 값을 다시 확인하세요.
        → ./oci_api_private_key.pem 이 OCI Console 에 등록한 키와 동일한지 확인."
fi

USER_NAME=$(.venv/bin/python -c "import sys,json;print(json.loads(sys.stdin.read())['user'])" <<< "$PROBE_RESULT")
AD_FIRST=$(.venv/bin/python -c "import sys,json;print(json.loads(sys.stdin.read())['ads'][0])" <<< "$PROBE_RESULT")
AUTO_SUBNET=$(.venv/bin/python -c "import sys,json;print(json.loads(sys.stdin.read())['subnet_id'])" <<< "$PROBE_RESULT")

ok "OCI 인증 성공 (user=$USER_NAME)"
ok "AD 자동 탐지: $AD_FIRST"

if [ -n "$AUTO_SUBNET" ]; then
    ok "공용 서브넷 자동 탐색: ${AUTO_SUBNET:0:60}..."
    SUBNET_ID="$AUTO_SUBNET"
else
    warn "기존 공용 서브넷이 없습니다."
    echo
    echo "  옵션:"
    echo "    1) Free Tier VCN/Subnet 자동 생성 (권장)"
    echo "    2) 직접 OCID 붙여넣기"
    SUBNET_CHOICE=$(ask "선택 (1 또는 2)" "1")

    if [ "$SUBNET_CHOICE" = "2" ]; then
        SUBNET_ID=$(ask "공용 서브넷 OCID" "")
        [ -n "$SUBNET_ID" ] || fail "OCID 가 비어있습니다."
    else
        step "[자동] VCN + Internet Gateway + Subnet 생성"
        SUBNET_ID=$(.venv/bin/python - <<'PY' 2>&1
import json
import sys
import oci

cfg = oci.config.from_file("./oci_config")
vnet = oci.core.VirtualNetworkClient(cfg)
compartment = cfg["tenancy"]

# VCN 생성
vcn = vnet.create_vcn(
    oci.core.models.CreateVcnDetails(
        cidr_block="10.0.0.0/16",
        compartment_id=compartment,
        display_name="free-tier-vcn",
    )
).data
oci.wait_until(vnet, vnet.get_vcn(vcn.id), "lifecycle_state", "AVAILABLE")

# Internet Gateway
ig = vnet.create_internet_gateway(
    oci.core.models.CreateInternetGatewayDetails(
        compartment_id=compartment,
        is_enabled=True,
        vcn_id=vcn.id,
        display_name="free-tier-ig",
    )
).data
oci.wait_until(vnet, vnet.get_internet_gateway(ig.id), "lifecycle_state", "AVAILABLE")

# 기본 라우트 테이블에 0.0.0.0/0 → IGW 추가
rt = vnet.get_route_table(vcn.default_route_table_id).data
vnet.update_route_table(
    rt.id,
    oci.core.models.UpdateRouteTableDetails(
        route_rules=[
            oci.core.models.RouteRule(
                destination="0.0.0.0/0",
                destination_type="CIDR_BLOCK",
                network_entity_id=ig.id,
            )
        ]
    ),
)

# 공용 Subnet 생성
sn = vnet.create_subnet(
    oci.core.models.CreateSubnetDetails(
        cidr_block="10.0.0.0/24",
        compartment_id=compartment,
        vcn_id=vcn.id,
        display_name="free-tier-subnet",
        prohibit_public_ip_on_vnic=False,
    )
).data
oci.wait_until(vnet, vnet.get_subnet(sn.id), "lifecycle_state", "AVAILABLE")

print(sn.id)
PY
)
        if [[ "$SUBNET_ID" != ocid1.subnet.* ]]; then
            fail "VCN 자동 생성 실패: $SUBNET_ID"
        fi
        ok "공용 서브넷 자동 생성: ${SUBNET_ID:0:60}..."
    fi
fi

# ---------- [3/4] Discord Webhook ----------
step "[3/4] Discord 알림 (선택)"
DISCORD_URL=$(ask "Discord Webhook URL (Enter=알림 없음)" "")

# ---------- [4/4] 최종 확인 ----------
step "[4/4] oci.env 작성"
if [ -f oci.env ]; then
    mv oci.env "oci.env.bak.$(date +%Y%m%d-%H%M%S)"
    ok "기존 oci.env → oci.env.bak.*"
fi

cat > oci.env <<EOF
# 자동 생성됨: $(date '+%Y-%m-%d %H:%M:%S')
OCI_CONFIG=./oci_config
OCT_FREE_AD=$AD_FIRST
OCI_REGIONS=ap-seoul-1,ap-chuncheon-1
DISPLAY_NAME=a1-free-arm
OCI_COMPUTE_SHAPE=VM.Standard.A1.Flex
SECOND_MICRO_INSTANCE=False
REQUEST_WAIT_TIME_SECS=90
SSH_AUTHORIZED_KEYS_FILE=$HOME/.ssh/oci_auto.pub
OCI_SUBNET_ID=$SUBNET_ID
OCI_IMAGE_ID=
OPERATING_SYSTEM="Canonical Ubuntu"
OS_VERSION=24.04
ASSIGN_PUBLIC_IP=true
BOOT_VOLUME_SIZE=50
DISCORD_WEBHOOK=$DISCORD_URL
EOF
ok "oci.env 생성 완료"

cat <<EOF

============================================================
 ${BOLD}${GREEN}셋업 완료.${NC}
 SSH 키는 첫 실행 시 자동 생성됩니다 (없을 때):
   공개키: ~/.ssh/oci_auto.pub
   개인키: ~/.ssh/oci_auto       ← 인스턴스 접속 시 사용

 다음:
   ${BOLD}./setup_init.sh${NC}    # 인스턴스 자동 생성 시작
   ${BOLD}./doctor.sh${NC}        # 셋업 진단
   ${BOLD}./stop.sh${NC}          # 백그라운드 프로세스 종료
============================================================
EOF
