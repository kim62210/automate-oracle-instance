# 오라클 클라우드 무료 ARM 인스턴스 자동 생성기

오라클 클라우드는 평생 무료로 사용할 수 있는 ARM 서버(4 CPU / 24GB 메모리)를 제공합니다.
하지만 인기가 너무 많아서 **"Out of host capacity"(자리 없음)** 오류로
대부분 만들지 못합니다.

이 스크립트는 **자리가 날 때까지 자동으로 계속 시도**하다가 성공하면
Discord 로 알려줍니다. 비개발자도 따라 할 수 있게 단계별로 안내합니다.

## 무엇이 만들어지나요?

| 항목 | 무료 ARM (권장) | 무료 AMD |
|------|----------------|---------|
| 종류 | VM.Standard.A1.Flex | VM.Standard.E2.1.Micro |
| CPU | 4코어 | 1코어 |
| 메모리 | 24GB | 1GB |
| 비용 | **0원 (평생)** | **0원 (평생)** |

## 따라하기 전에 준비할 것

1. **오라클 클라우드 계정** - 카드 등록은 필요하지만 청구되지 않습니다 (무료 등급 한정).
2. **터미널 사용 가능한 컴퓨터** - macOS / Linux / Windows(WSL) 모두 가능.
3. **(선택) Discord 서버** - 알림을 받고 싶다면 필요합니다.

---

## STEP 1. 오라클 클라우드에서 API 키 만들기

API 키는 "내가 이 스크립트에게 OCI 작업을 시킬 권한을 줍니다"라는 증명서입니다.

### 1-1. OCI Console 접속

1. https://cloud.oracle.com 접속 → 로그인
2. 우측 상단의 **사람 모양 아이콘** 클릭 → **내 프로필(My Profile)**

### 1-2. API 키 추가

1. 좌측 메뉴에서 **API 키(API Keys)** 클릭
2. **API 키 추가(Add API Key)** 버튼 클릭
3. **API 키 쌍 생성(Generate API Key Pair)** 선택
4. **개인 키 다운로드(Download Private Key)** 버튼 클릭
   → `.pem` 파일이 다운로드됩니다. **잘 보관하세요.**
5. **추가(Add)** 클릭
6. 화면에 나타나는 **구성 파일 미리보기(Configuration File Preview)** 내용을
   전부 **복사**합니다. 다음 단계에서 사용합니다.

복사한 내용은 이렇게 생겼습니다:
```
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=<path to your private keyfile> # TODO
```

---

## STEP 2. 컴퓨터에 키 파일 저장하기

### 2-1. 폴더 만들기

터미널을 열고 (macOS: `command + space` → "터미널" 검색):
```bash
mkdir -p ~/.oci
```

### 2-2. 다운로드한 개인 키 옮기기

```bash
mv ~/Downloads/*.pem ~/.oci/oci_api_private_key.pem
chmod 600 ~/.oci/oci_api_private_key.pem
```

### 2-3. config 파일 만들기

```bash
nano ~/.oci/config
```
- 1-2 단계에서 복사한 내용을 **붙여넣기** (macOS: `command + v`)
- 마지막 줄 `key_file=...` 부분을 다음과 같이 바꿉니다:
  ```
  key_file=/Users/본인_계정명/.oci/oci_api_private_key.pem
  ```
  > 본인 계정명은 터미널에서 `whoami` 명령으로 확인할 수 있습니다.
- **저장**: `Ctrl + O` → `Enter` → `Ctrl + X`

---

## STEP 3. 가용 도메인(AD) 확인하기

가용 도메인은 "데이터센터 안의 어느 구역에서 서버를 만들지" 정하는 값입니다.
대부분 `AD-1` 입니다. 확인 방법:

1. OCI Console 좌측 햄버거 메뉴 → **컴퓨트(Compute)** → **인스턴스(Instances)**
2. **인스턴스 생성(Create Instance)** 버튼 클릭 (실제로 만들 필요는 없습니다)
3. **배치(Placement)** 항목에서 **이름(Name)** 옆에 표시된 값 확인
   - 예: `xxxx:AP-SEOUL-1-AD-1` → `AD-1` 사용
4. 확인만 하고 **취소(Cancel)** 누르고 나오기

---

## STEP 3-1. (신규 계정만) VCN/Subnet 생성

**오라클 클라우드를 처음 쓴다면 가상 네트워크(VCN)가 없어서
이 스크립트가 어디에 인스턴스를 만들지 못 찾습니다.**
이미 VCN 이 있다면 이 단계는 건너뛰세요.

1. OCI Console 햄버거 메뉴 → **네트워킹(Networking)**
   → **가상 클라우드 네트워크(Virtual Cloud Networks)**
2. **VCN 마법사 시작(Start VCN Wizard)** 버튼 클릭
3. **인터넷 연결성을 가진 VCN 생성(Create VCN with Internet Connectivity)** 선택
4. VCN 이름 입력 (예: `free-tier-vcn`) → 나머지 기본값 그대로 → **다음/생성**

생성 후, **서브넷 OCID 를 복사해서 메모**해 둡니다:
- 만든 VCN 클릭 → 좌측 **서브넷(Subnets)** → 공용 서브넷 클릭
- 우측 OCID 옆 **복사(Copy)** 버튼 클릭

> 💡 멀티 리전(`ap-seoul-1,ap-chuncheon-1` 등)을 쓰려면
> **각 리전마다** VCN/Subnet 을 만들어야 합니다.
> (먼저 우측 상단 리전 드롭다운으로 리전 변경 후 같은 절차 반복)

---

## STEP 4. SSH 키 (자동 생성됨, 직접 만들 필요 없음)

서버에 접속하려면 자물쇠와 열쇠 같은 SSH 키 한 쌍이 필요합니다.
**스크립트 첫 실행 시 자동으로 생성**되니 신경 쓰지 않아도 됩니다.

자동 생성되는 파일 (기본값):
- 공개키: `~/.ssh/id_oci_auto.pub`
- 개인키: `~/.ssh/id_oci_auto_private` ← **서버 SSH 접속 시 사용**

> 이미 본인 SSH 키가 있고 그걸 쓰고 싶다면 STEP 6 에서 `oci.env` 의
> `SSH_AUTHORIZED_KEYS_FILE` 경로만 본인 키로 바꾸면 됩니다.

---

## STEP 5. 이 스크립트 받기

```bash
cd ~
git clone https://github.com/kim62210/automate-oracle-instance.git
cd automate-oracle-instance
```

> Git 이 없다면 macOS 는 자동으로 설치를 안내합니다.
> Linux 는 `sudo apt install git` 으로 설치하세요.

---

## STEP 6. 설정 파일 만들기

### 옵션 A. **대화형 마법사 (추천)**

질문에 답만 하면 됩니다:
```bash
./setup_env.sh
```

### 옵션 B. **직접 편집**

```bash
cp oci.env.example oci.env
nano oci.env
```

**대부분의 항목은 이미 합리적인 기본값이 채워져 있습니다.**
실제로 본인이 채워야 할 항목은 보통 1가지뿐입니다:

| 항목 | 채워야 할 때 |
|------|--------------|
| `OCI_SUBNET_ID` | 신규 OCI 계정인 경우 (STEP 3-1 에서 만든 서브넷 OCID) |
| `DISCORD_WEBHOOK` | 알림 받고 싶을 때 (STEP 7 참고) |

기본값으로 동작하는 항목 (수정 불필요):
- `OCI_CONFIG=~/.oci/config` -- STEP 1~2 표준 위치
- `SSH_AUTHORIZED_KEYS_FILE=~/.ssh/id_oci_auto.pub` -- 없으면 자동 생성됨
- `OCI_REGIONS=ap-seoul-1,ap-chuncheon-1` -- 한국 리전
- `OPERATING_SYSTEM=Canonical Ubuntu`, `OS_VERSION=24.04`
- `REQUEST_WAIT_TIME_SECS=90` -- OCI 차단 회피 권장값

---

## STEP 7. (선택) Discord 알림 설정

### 7-1. Discord 서버에서 웹훅 만들기

1. Discord 서버 접속 → **서버 설정(Server Settings)**
2. **연동(Integrations)** → **웹후크(Webhooks)** → **새 웹후크(New Webhook)**
3. 이름과 채널 정한 뒤 **URL 복사(Copy Webhook URL)** 클릭

### 7-2. oci.env 에 붙여넣기

`oci.env` 파일에서 다음 줄을 찾아 복사한 URL 을 붙여넣습니다:
```bash
DISCORD_WEBHOOK=https://discord.com/api/webhooks/.....
```

알림을 안 받으려면 빈 값으로 두면 됩니다.

---

## STEP 8. 셋업 점검 (강력 추천)

실행 전에 셋업 상태를 진단해 주는 `doctor.sh` 가 있습니다.
어떤 항목이 비었고 어떤 게 OK 인지 한눈에 보여줍니다.

```bash
./doctor.sh
```

검사 항목 (8단계):
1. `oci.env` 파일 존재
2. `OCI_CONFIG` 경로/내용 (필수 5개 키 + .pem 실재 여부)
3. `OCT_FREE_AD` 설정 여부
4. SSH 공개키 (없으면 첫 실행 시 자동 생성됨을 안내)
5. `OCI_SUBNET_ID` (신규 계정 안내)
6. Python venv + 의존 패키지
7. **OCI 인증 (실제 read-only API 호출)**
8. Discord webhook 설정 여부 (`./doctor.sh --discord` 로 실제 전송 테스트)

요약 줄에서 `[FAIL] 0` 이면 다음 단계로 진행 OK.

---

## STEP 9. 실행!

```bash
./setup_init.sh
```

처음 실행하면 필요한 라이브러리를 자동 설치합니다 (몇 분 소요).
실행 결과는 화면과 `setup_init.log` 에 기록됩니다.

성공적으로 시작되면 백그라운드에서 계속 시도합니다:
- **자리가 없을 때**: 90초 후 다시 시도 (Discord 로 10회마다 진행 상황 알림)
- **자리가 났을 때**: 인스턴스 생성 + Discord 로 성공 알림 + `INSTANCE_CREATED` 파일 생성
- **에러 발생 시**: `ERROR_IN_CONFIG.log` 또는 `setup_init.log` 에 사유 기록

### 중간에 멈추기

```bash
# 어느 프로세스가 도는지 확인
ps aux | grep main.py

# 종료 (PID 는 위 명령으로 확인)
kill <PID>
```

### 다시 실행 (라이브러리 재설치 안 함)

```bash
./setup_init.sh rerun
```

---

## 자주 발생하는 문제

### 우선 `./doctor.sh` 부터 실행

대부분의 문제는 진단 스크립트로 1초 안에 원인이 드러납니다.
```bash
./doctor.sh
```
`[FAIL]` 표시된 항목의 안내 메시지가 가장 정확한 해결책입니다.

### "ERROR_IN_CONFIG.log 가 생겼어요" / 셋업이 멈춰요

가장 흔한 원인 4가지:

| 메시지 | 원인 | 해결 |
|--------|------|------|
| `OCI_CONFIG 가 비어있습니다` | `oci.env` 파일을 안 만듦 | `cp oci.env.example oci.env` 부터 다시 |
| `파일을 찾을 수 없습니다` | 경로 오타 / `~` 사용 | 전체 경로(`/Users/...`)로 수정 |
| `[DEFAULT] 의 user= 항목이 없습니다` | OCI Config 내용 비어있음 | STEP 1-2 의 미리보기 내용 다시 복사 |
| `값에 공백이 포함돼 있습니다` | 줄 끝/값에 공백 | 공백 제거, 따옴표 사용 X |

진단 명령:
```bash
cat ERROR_IN_CONFIG.log              # 실제 에러 메시지 확인
cat oci.env | grep OCI_CONFIG        # 경로 확인
cat $(grep '^OCI_CONFIG=' oci.env | cut -d= -f2)  # config 파일 내용 확인
```

### Discord 알림이 안 와요

```bash
# 웹훅 URL 이 정확한지 직접 테스트
curl -H "Content-Type: application/json" \
     -X POST \
     -d '{"content":"테스트"}' \
     "$(grep '^DISCORD_WEBHOOK=' oci.env | cut -d= -f2)"
```
"테스트" 가 Discord 채널에 뜨면 정상.

### "Out of host capacity" 가 계속 나와요

**정상입니다.** ARM 무료 자원은 매우 부족해서 수 시간 ~ 며칠 걸릴 수 있습니다.
- 한국 리전 둘 다(`ap-seoul-1,ap-chuncheon-1`) 시도하면 확률이 높아집니다.
- Discord 알림이 설정돼있으면 진행 상황이 자동으로 옵니다.
- 컴퓨터/오라클 마이크로 인스턴스에서 계속 켜둬야 합니다 (꺼두면 시도 중단).

---

## 만든 후 서버 접속하기

```bash
ssh -i ~/.ssh/id_ed25519_oci ubuntu@<공용 IP>
```
공용 IP 는 OCI Console > 컴퓨트 > 인스턴스 상세 페이지에서 확인할 수 있고,
`INSTANCE_CREATED` 파일에도 정보가 적혀 있습니다.

---

## 환경변수 빠른 참조 (oci.env)

각 항목을 어디서 얻는지 한눈에 정리한 표입니다.
자세한 단계는 위 STEP 1~7 참고.

### 필수 항목 (기본값 그대로 사용 가능)

| 변수 | 기본값 | 채워야 할 때 |
|------|--------|--------------|
| `OCI_CONFIG` | `~/.oci/config` | STEP 1~2 표준 위치를 따랐다면 그대로 |
| `OCT_FREE_AD` | `AD-1` | 대부분 그대로 (다른 AD 라면 STEP 3) |
| `SSH_AUTHORIZED_KEYS_FILE` | `~/.ssh/id_oci_auto.pub` | 없으면 자동 생성. 본인 키 쓰려면 경로만 변경 |

### 선택 항목

| 변수 | 무엇인가요? | 어디서 얻나요? / 기본값 |
|------|------------|----------------------|
| `OCI_REGIONS` | 시도할 리전(쉼표 구분) | OCI Console 우측 상단 리전 드롭다운. 예) `ap-seoul-1,ap-chuncheon-1` |
| `DISPLAY_NAME` | 인스턴스 이름 | 자유롭게. 기본값 `a1-free-arm` |
| `OCI_COMPUTE_SHAPE` | 서버 종류 | `VM.Standard.A1.Flex` (ARM 권장) 또는 `VM.Standard.E2.1.Micro` |
| `SECOND_MICRO_INSTANCE` | 2번째 Micro 만들 때만 `True` | `False` |
| `REQUEST_WAIT_TIME_SECS` | 재시도 간격(초) | 권장 `90` (60 미만은 OCI 차단 위험) |
| `OCI_SUBNET_ID` | 서브넷 OCID | **신규 계정은 STEP 3-1 로 VCN 생성 후 OCID 입력 필요.** 기존 VCN 이 있으면 자동 탐색 |
| `OCI_IMAGE_ID` | 특정 이미지 OCID | OCI Console → 컴퓨트 → 이미지. 비우면 아래 OS+버전으로 자동 탐색 |
| `OPERATING_SYSTEM` ⚠️ | OS 이름 | `Canonical Ubuntu` (기본) — `OCI_IMAGE_ID` 비울 때 정확해야 함 |
| `OS_VERSION` ⚠️ | OS 버전 | `24.04` (기본) — `OCI_IMAGE_ID` 비울 때 정확해야 함 |
| `ASSIGN_PUBLIC_IP` | 공용 IP 자동 할당 | `true` 또는 `false` |
| `BOOT_VOLUME_SIZE` | 부트 디스크 GB (최소 50) | `50` |
| `DISCORD_WEBHOOK` | Discord 알림 URL | Discord 서버 설정 → 연동 → 웹후크 → URL 복사 (STEP 7) |

> 💡 **모르는 항목은 비워두거나 기본값을 그대로 사용하면 됩니다.**
> `oci.env.example` 파일에는 항목별로 더 자세한 클릭 경로가 주석으로 적혀 있습니다.
>
> ⚠️ 표시 항목은 "조건부 필수" — 다른 값(`OCI_IMAGE_ID`)이 비어있을 때
> 정확하게 채워져 있어야 합니다.

---

## 로그 파일 안내

| 파일 | 용도 |
|------|------|
| `setup_init.log` | Python 의 모든 출력 (예외 메시지 포함) |
| `launch_instance.log` | OCI API 호출 + 재시도 기록 |
| `setup_and_info.log` | 시작 시점 설정값 |
| `ERROR_IN_CONFIG.log` | 설정 오류 사유 (정상 동작 시 자동 삭제) |
| `INSTANCE_CREATED` | 생성된 인스턴스 정보 |

---

## 라이선스

MIT License - [mohankumarpaluru/oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) 기반
