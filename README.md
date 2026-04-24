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

## STEP 4. SSH 키 만들기

서버에 접속하려면 자물쇠와 열쇠 같은 SSH 키 한 쌍이 필요합니다.
이미 있다면 이 단계는 건너뛰어도 됩니다.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_oci -N ""
```
- 두 개의 파일이 생성됩니다:
  - `~/.ssh/id_ed25519_oci` (개인 키 - 절대 공유 금지)
  - `~/.ssh/id_ed25519_oci.pub` (공개 키 - 서버에 등록할 키)

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

최소한 아래 4개 항목만 채우면 됩니다:
```bash
OCI_CONFIG=/Users/본인_계정명/.oci/config
OCT_FREE_AD=AD-1
OCI_REGIONS=ap-seoul-1,ap-chuncheon-1
SSH_AUTHORIZED_KEYS_FILE=/Users/본인_계정명/.ssh/id_ed25519_oci.pub
```

> **주의**: 경로 안에 `~` 를 쓰지 말고 `/Users/...` 처럼 **전체 경로**를 적으세요.
> `whoami` 로 본인 계정명 확인 가능합니다.

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

## STEP 8. 실행!

```bash
./setup_init.sh
```

처음 실행하면 필요한 라이브러리를 자동 설치합니다 (몇 분 소요).
실행 결과는 화면과 `setup_init.log` 에 기록됩니다.

성공적으로 시작되면 백그라운드에서 계속 시도합니다:
- **자리가 없을 때**: 60초 후 다시 시도 (Discord 로 10회마다 진행 상황 알림)
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
