# docs/agent/local-execution.md — 로컬 셸 자동화

[oci-onboarding.md](oci-onboarding.md) 에서 `.pem` 파일 + 미리보기 텍스트를 확보한 뒤, 에이전트가 사용자 머신의 셸에서 인스톨러/마법사를 자동 실행하는 시나리오입니다.

---

## STEP 1. 인스톨러 실행

OS 별로 한 줄. 반드시 사용자 동의 후 실행.

### macOS

```bash
curl -fsSL https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/macos/install.sh | bash
```

기대 동작:
1. brew/git/python3 확인 → 부족하면 `brew install`
2. `~/automate-oracle-instance` 에 git clone (있으면 git pull)
3. `./setup.sh` 인터랙티브 실행 → 사용자/에이전트 입력 대기
4. 완료 시 `./setup_init.sh` 자동 실행 → 백그라운드 인스턴스 생성 시작

### Windows (WSL 필요)

```powershell
iwr -useb https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/windows/install.ps1 | iex
```

기대 동작 (WSL 내부에서):
1. WSL 미설치 시 안내 후 종료 → 사용자가 관리자 PowerShell 에서 `wsl --install` 후 재부팅 필요
2. WSL 안에서 apt 의존성 자동 설치
3. clone + `./setup.sh` + `./setup_init.sh`

### 사전 점검 (에이전트 자체 진단)

인스톨러 실행 전 다음 명령 결과를 LLM 컨텍스트로 보내고 분기:

| 명령 | 정상 응답 | 비정상 시 처리 |
|---|---|---|
| `uname -s` (Unix) / `$PSVersionTable.PSVersion` (Windows) | `Darwin` / `Linux` / 5+ | 지원 OS 안내 |
| `which curl` (mac) / `Get-Command iwr` (Win) | 경로 출력 | 사용자에게 설치 안내 |
| (Win) `wsl --status` | "기본 배포..." 출력 + exit 0 | "WSL 사전 설치 필요" 안내 (자동 install 시도 X) |

---

## STEP 2. `./setup.sh` 4-입력 자동 채움

`./setup.sh` 는 4개의 사용자 입력을 받습니다. 에이전트가 채우는 패턴:

### [1/4] `.pem` 경로

| 상황 | 입력 |
|---|---|
| `.pem` 이 `~/Downloads/` 또는 (WSL) `/mnt/c/Users/*/Downloads/` 에 있음 | **Enter** (자동 감지) |
| 다른 경로 | 절대경로 한 줄 |

자동 감지 신호: setup.sh 의 출력 `자동 감지된 가장 최근 .pem: <경로>` 가 사용자 의도와 일치하면 Enter.

### [2/4] 구성 파일 미리보기

setup.sh 가 `cat > "$TMP_CFG" < /dev/tty` 로 stdin 을 통째로 읽음. 종료 신호는 EOF (Ctrl+D).

에이전트가 stdin 으로 채우는 방법:

#### 패턴 A: stdin pipe (가장 견고)

```bash
echo "$PREVIEW_TEXT" | ./setup.sh   # ❌ 동작 안 함 — setup.sh 가 < /dev/tty 로 직접 읽기 때문
```

**위 방법은 안 됩니다.** setup.sh 가 의도적으로 `/dev/tty` 를 직접 읽도록 설계됨. 따라서 다음 중 하나:

#### 패턴 B: pty (의사 터미널) 자동화 — 추천

Python `pexpect`, Node `node-pty`, Go `creack/pty` 등으로 의사 터미널을 만들어 setup.sh 띄우고 단계별 입력 주입:

```python
# 의사 코드
import pexpect

child = pexpect.spawn("./setup.sh", cwd=os.path.expanduser("~/automate-oracle-instance"))

# [1/4] .pem
child.expect(r"Enter=그대로 사용|절대경로 입력")
child.sendline("")  # Enter (자동 감지)

# [2/4] preview
child.expect(r"빈 줄에서 Ctrl\+D")
child.send(preview_text + "\n")
child.send("\x04")  # Ctrl+D (EOF)

# [3/4] subnet (자동 탐색 성공 시 이 프롬프트 안 뜸)
idx = child.expect([r"선택 \(1 또는 2\)", r"\[4/4\]", pexpect.EOF])
if idx == 0:
    child.sendline("1")  # VCN 자동 생성

# [4/4] discord
child.expect(r"Webhook URL")
child.sendline(discord_url or "")

child.expect(pexpect.EOF, timeout=180)
```

#### 패턴 C: expect 스크립트 (Tcl 기반)

```tcl
spawn ./setup.sh
expect "Enter=그대로 사용"
send "\r"
expect "Ctrl\+D"
send "$preview_text\r\x04"
...
```

#### 패턴 D: 인터랙티브 wrapper 우회 (가장 단순)

미리보기 텍스트와 `.pem` 경로를 이미 알고 있다면 setup.sh 를 거치지 않고 직접 파일 작성:

```bash
# 에이전트가 직접 처리
cd ~/automate-oracle-instance

# [1/4] 대체
cp "$PEM_PATH" ./oci_api_private_key.pem
chmod 600 ./oci_api_private_key.pem

# [2/4] 대체
ABS_PEM="$(pwd)/oci_api_private_key.pem"
cat > ./oci_config <<'PREVIEW'
$PREVIEW_TEXT
PREVIEW
sed -i.bak -E "s|^key_file=.*|key_file=$ABS_PEM|" ./oci_config && rm ./oci_config.bak

# OCI 인증 + AD 탐지 + Subnet 탐색은 setup.sh 의 inline python 블록을 직접 호출
# 또는 간단한 oci_probe.py 헬퍼를 작성

# oci.env 직접 작성
cat > ./oci.env <<EOF
OCI_CONFIG=./oci_config
OCT_FREE_AD=AD-1
OCI_REGIONS=ap-seoul-1,ap-chuncheon-1
DISPLAY_NAME=a1-free-arm
OCI_COMPUTE_SHAPE=VM.Standard.A1.Flex
SECOND_MICRO_INSTANCE=False
REQUEST_WAIT_TIME_SECS=90
SSH_AUTHORIZED_KEYS_FILE=$HOME/.ssh/oci_auto.pub
OCI_SUBNET_ID=
OCI_IMAGE_ID=
OPERATING_SYSTEM="Canonical Ubuntu"
OS_VERSION=24.04
ASSIGN_PUBLIC_IP=true
BOOT_VOLUME_SIZE=50
DISCORD_WEBHOOK=$DISCORD_URL
EOF
```

> 패턴 D 는 setup.sh 의 OCI 인증 검증 / AD 자동 탐지 / Subnet 자동 생성을 우회합니다. 그 검증을 별도로 수행해야 안전. 패턴 B 가 가장 안전하고 표준 흐름과 일치.

### [3/4] Subnet (조건부)

- 자동 탐색 성공 시 setup.sh 가 이 프롬프트를 띄우지 않음
- 프롬프트가 뜨면:
  - 사용자가 OCID 명시 → 그대로 입력
  - 명시 X → `1` (Free Tier VCN 자동 생성)

### [4/4] Discord Webhook URL

- 사용자 설정값 또는 빈 줄 (Enter)
- URL 형식 검증: `^https://(discord\.com|discordapp\.com)/api/webhooks/\d+/[A-Za-z0-9_-]+$`

---

## STEP 3. `./setup_init.sh` 백그라운드 실행

setup.sh 가 정상 종료되면 자동으로 setup_init.sh 가 호출됩니다 (인스톨러 흐름). 직접 호출:

```bash
cd ~/automate-oracle-instance
./setup_init.sh
```

기대 동작:
- `.venv` 자동 생성 + 의존성 설치 (첫 실행 시)
- `python3 main.py` 백그라운드 실행 → `.main.pid` 에 PID 기록 + `setup_init.log` 에 로그
- 10초 + 60초 후 셋업 결과 판정 (성공 / 재시도 중 / 에러)

에이전트는 다음 출력 패턴을 모니터링:

| 패턴 | 의미 | 후속 동작 |
|---|---|---|
| `[INFO] main.py 실행 시작 (PID: <N>)` | 정상 시작 | 모니터링 단계로 |
| `[성공] 인스턴스가 생성되었거나 ...` | 첫 시도에 성공 | `cat INSTANCE_CREATED` 후 사용자 보고 |
| `[INFO] 스크립트가 정상적으로 재시도 중입니다.` | 자리 부족 — 정상 | 백그라운드 모니터링 |
| `[ERROR] 설정 오류가 발생했습니다.` | `ERROR_IN_CONFIG.log` 확인 후 회복 | STEP 5 |

---

## STEP 4. 진행 모니터링

백그라운드 실행 중 다음을 폴링 (예: 5분 간격):

```bash
cd ~/automate-oracle-instance

# 1. 인스턴스 생성 완료?
if [ -s INSTANCE_CREATED ]; then
    echo "DONE"
    cat INSTANCE_CREATED
    exit 0
fi

# 2. 설정 오류?
if [ -s ERROR_IN_CONFIG.log ]; then
    echo "CONFIG_ERROR"
    cat ERROR_IN_CONFIG.log
    exit 1
fi

# 3. 진행 로그 — 최근 5줄만 (전체 길어질 수 있음)
tail -n 5 launch_instance.log 2>/dev/null

# 4. 백그라운드 살아있나
if [ -f .main.pid ] && kill -0 "$(cat .main.pid)" 2>/dev/null; then
    echo "RUNNING pid=$(cat .main.pid)"
else
    echo "DEAD"
    tail -n 30 setup_init.log
fi
```

> ⚠️ Discord webhook 설정되어 있으면 진행 알림이 자동 푸시되므로, 에이전트 폴링은 보조 수단.

---

## STEP 5. 에러 회복

### `ERROR_IN_CONFIG.log` 패턴별 대응

| 메시지 | 원인 | 자동 회복 |
|---|---|---|
| `OCI_CONFIG 가 비어있습니다` | oci.env 누락/깨짐 | `./setup.sh` 다시 실행 (oci.env 재생성) |
| `OCI_CONFIG 경로의 파일을 찾을 수 없습니다` | oci_config 경로 오타 | oci.env 의 OCI_CONFIG 라인 수정 후 재실행 |
| `[DEFAULT] 의 user= 항목이 없습니다` | oci_config 내용 비정상 | [oci-onboarding.md](oci-onboarding.md) STEP 1 다시 → 새 미리보기 |
| `값에 공백이 포함돼 있습니다` | 줄 끝 공백 등 | 자동 trim 후 재실행 |
| OCI 인증 실패 (`Forbidden`, `NotAuthenticated`) | API 키 폐기 / fingerprint 불일치 | 사용자 보고 → OCI Console 에서 키 재추가 |

### `./doctor.sh` 자동 실행 + 결과 파싱

```bash
./doctor.sh > doctor.out 2>&1
PASS=$(grep -c "^  \[OK\]" doctor.out)
FAIL=$(grep -c "^  \[FAIL\]" doctor.out)
WARN=$(grep -c "^  \[WARN\]" doctor.out)

if [ "$FAIL" -gt 0 ]; then
    grep -A 1 "\[FAIL\]" doctor.out  # FAIL 항목과 안내 메시지 추출
    # → 위 표 매칭 후 자동 회복 또는 사용자 보고
fi
```

---

## STEP 6. 정리 / 종료

### 백그라운드 종료

```bash
./stop.sh
```

### 인스턴스 생성 후

`INSTANCE_CREATED` 가 생성되면 자동 시도가 멈춘 게 아니라 **종료 신호**. main.py 프로세스도 자동 종료. 에이전트는:

```bash
# 결과 추출
INSTANCE_INFO=$(cat INSTANCE_CREATED)
PUBLIC_IP=$(grep -oE 'public_ip[: ]+[0-9.]+' INSTANCE_CREATED | head -1)

# 사용자에게 보고
echo "성공: 공용 IP = $PUBLIC_IP"
echo "SSH 접속: ssh -i ~/.ssh/oci_auto ubuntu@$PUBLIC_IP"
```

> 🔒 SSH 개인키 (`~/.ssh/oci_auto`) 의 내용은 절대 출력 금지. 경로만 안내.

---

## 부록 A. 에이전트 폴링 백오프 가이드

자리가 나기까지 수 시간 ~ 며칠 걸릴 수 있습니다. 폴링 간격 권장:

| 경과 시간 | 폴링 간격 |
|---|---|
| 0 ~ 30분 | 5분 |
| 30분 ~ 6시간 | 30분 |
| 6시간 이후 | 1시간 |

또는 폴링 대신 **Discord webhook 으로 알림 받는 게 비용 효율적**. 에이전트는 인스톨러 종료 후 사용자에게 "Discord 채널에 알림이 오면 다시 호출하세요" 라고 안내하고 백오프하는 것도 방법.

---

## 부록 B. 비대화형 환경 (CI / 컨테이너) 에서의 우회

stdin /dev/tty 가 없는 환경(예: GitHub Actions, Docker 빌드)에서는 위 패턴 B (pty) 가 필수. 또는 패턴 D (직접 파일 작성) 사용. setup.sh 자체는 인터랙티브 전용으로 설계되었으므로 비대화형은 본 문서가 직접 지원하지 않습니다.
