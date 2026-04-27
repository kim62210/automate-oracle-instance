# 오라클 클라우드 무료 ARM 인스턴스 자동 생성기

오라클 클라우드는 평생 무료로 사용할 수 있는 ARM 서버(4 CPU / 24GB 메모리)를 제공합니다.
하지만 인기가 너무 많아서 **"Out of host capacity"(자리 없음)** 오류로 대부분 만들지 못합니다.

이 스크립트는 **자리가 날 때까지 자동으로 계속 시도**하다가 성공하면 Discord 로 알려줍니다.
비개발자도 따라 할 수 있게 단계별로 안내합니다.

## 무엇이 만들어지나요?

| 항목 | 무료 ARM (권장) | 무료 AMD |
|------|----------------|---------|
| 종류 | VM.Standard.A1.Flex | VM.Standard.E2.1.Micro |
| CPU | 4코어 | 1코어 |
| 메모리 | 24GB | 1GB |
| 비용 | **0원 (평생)** | **0원 (평생)** |

## 따라하기 전에 준비할 것

1. **오라클 클라우드 계정** -- STEP 0 에서 만듭니다 (카드 등록 필요, 청구 없음).
2. **터미널 사용 가능한 컴퓨터**
   - macOS: 기본 "터미널" 앱
   - Linux: 기본 터미널
   - Windows: WSL2 (Ubuntu) 권장 -- https://learn.microsoft.com/ko-kr/windows/wsl/install
3. **Python 3.10+ / git** (없으면 [부록 D](#부록-d-도구-설치-안내) 참고)
4. **(선택) Discord 서버** -- 알림을 받고 싶다면 필요합니다.

---

## 빠른 시작 (부트스트랩 인스톨러, 강력 권장)

비개발자라면 **명령 한 줄 또는 더블클릭** 으로 의존성 설치 + git clone + OOBE 마법사까지 자동 진행됩니다.

### 0) OCI Console 에서 미리 준비 (브라우저, 5분)

1. **OCI 가입** -- [STEP 0](#step-0-오라클-클라우드-계정-만들기) 참고 (이미 있으면 패스)
2. **API 키 추가 + 개인 키(.pem) 다운로드 + 구성 파일 미리보기 복사** -- [STEP 1](#step-1-oci-console-에서-api-키-만들기) 참고

### 1) 인스톨러 실행

#### macOS

**옵션 A. 터미널 한 줄 (가장 간단)**
```bash
curl -fsSL https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/macos/install.sh | bash
```

**옵션 B. 더블클릭**
1. [`installers/macos/`](installers/macos/) 폴더 다운로드
2. 터미널에서 `chmod +x OciFreeArm.command install.sh` (한 번만)
3. `OciFreeArm.command` 우클릭 → **열기**

#### Windows (WSL 필요)

**옵션 A. PowerShell 한 줄 (가장 간단)**
```powershell
iwr -useb https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/windows/install.ps1 | iex
```

**옵션 B. 더블클릭**
1. [`installers/windows/`](installers/windows/) 폴더 다운로드
2. `OciFreeArm.cmd` 더블클릭

> ⚠️ Windows 는 **WSL (Ubuntu) 가 미리 설치되어 있어야 합니다.**
> 인스톨러는 WSL 자체를 자동 설치하지 않고, 미설치 시 안내 메시지 후 종료합니다.
> 설치 방법: 관리자 PowerShell 에서 `wsl --install` 실행 후 재부팅. 자세한 내용은 [installers/README.md](installers/README.md) 참고.

### 2) 인스톨러가 자동으로 처리하는 것

| 단계 | 자동 |
|---|---|
| 의존성 확인/설치 | macOS: `brew install git python@3.12` (brew 없으면 안내) <br/> Windows: WSL 안에서 `apt install git python3 python3-venv` |
| 레포 받기 | `~/automate-oracle-instance` 에 clone (있으면 `git pull`) |
| OOBE 마법사 (`./setup.sh`) | 4-입력만 받고 나머지(.pem 이동, oci_config 작성, OCI 인증, AD 탐지, Subnet 자동 탐색/생성, oci.env 작성) 모두 자동 |
| 인스턴스 자동 생성 (`./setup_init.sh`) | 백그라운드에서 자리 날 때까지 90초마다 재시도 |

### 3) OOBE 마법사 안에서 받는 4-입력

| 단계 | 입력 | 자동 처리 |
|---|---|---|
| **[1/4]** `.pem` 배치 | Enter (또는 다른 경로) | `~/Downloads` 의 가장 최근 `.pem` 자동 감지 (WSL 환경은 Windows Downloads 까지 탐색) → 레포 폴더로 이동 + 권한 600 |
| **[2/4]** 구성 파일 미리보기 | 박스 내용 통째로 붙여넣고 Ctrl+D | `oci_config` 자동 생성, `key_file=` 라인 절대경로 자동 치환 |
| **(자동)** OCI 인증 + AD 탐지 + 공용 서브넷 탐색 | 없음 | OCI API 호출로 검증, AD 자동 결정, 기존 VCN/Subnet 자동 발견 |
| **[3/4]** 서브넷 (필요 시) | Enter (자동 생성) 또는 1/2 선택 | 신규 계정이면 Free Tier VCN/IGW/Subnet 자동 생성 |
| **[4/4]** Discord Webhook | URL 또는 Enter | `oci.env` 에 기록 |

### 4) 셋업 점검 / 중지 / 접속

레포 디렉토리(`~/automate-oracle-instance`)에서:
```bash
./doctor.sh           # 설정 진단
./stop.sh             # 백그라운드 main.py 안전 종료
cat INSTANCE_CREATED  # 생성된 인스턴스 정보 (공용 IP)
```

자동 생성된 SSH 키로 접속:
```bash
ssh -i ~/.ssh/oci_auto ubuntu@<공용IP>
```

---

## 빠른 시작 (수동 git clone)

인스톨러를 안 쓰고 직접 진행하려는 경우:
```bash
cd ~
git clone https://github.com/kim62210/automate-oracle-instance.git
cd automate-oracle-instance
./setup.sh         # 4-입력 OOBE 마법사
./setup_init.sh    # 인스턴스 자동 생성 시작
```
이후 흐름과 입력은 위 [3) OOBE 마법사 안에서 받는 4-입력](#3-oobe-마법사-안에서-받는-4-입력) 표와 동일합니다.

---

## AI 에이전트로 진행하기 (선택)

Claude Code, Codex CLI, Cursor 등 **브라우저 컨트롤러를 가진 AI 에이전트**가 OCI Console 클릭 작업까지 사용자를 대신해 처리할 수 있도록 별도 가이드를 제공합니다.

대상: Playwright / Chrome DevTools (CDP) / Puppeteer / Selenium 등을 도구로 가진 LLM 기반 에이전트.

진입 문서:
- [AGENTS.md](AGENTS.md) — 에이전트가 자동 인식하는 표준 진입 문서. 허용/금지 작업, 표준 흐름, 도구 매핑
- [docs/agent/oci-onboarding.md](docs/agent/oci-onboarding.md) — OCI Console 단계별 시나리오 (한/영 라벨, role/aria-label hint, 실패 폴백, Playwright 의사 코드)
- [docs/agent/local-execution.md](docs/agent/local-execution.md) — 인스톨러 자동 실행 / `./setup.sh` 4-입력 stdin 자동 채움 (pty 패턴) / 모니터링 / 에러 회복
- [docs/agent/secrets-handling.md](docs/agent/secrets-handling.md) — `.pem` / OCID / fingerprint / Discord webhook 마스킹 정책

> ⚠️ **OCI 계정 로그인은 반드시 사용자가 직접** 진행하세요. 에이전트가 비밀번호/2FA 를 입력해서는 안 됩니다.
> 에이전트는 사용자가 로그인 완료한 브라우저 세션을 인계받아 그 다음 작업 (API 키 추가, .pem 다운, 미리보기 복사) 부터 처리합니다.

---

## STEP 0. 오라클 클라우드 계정 만들기 (이미 있으면 STEP 1)

1. https://www.oracle.com/cloud/free/ 접속 → **무료 계층 시작(Start for Free)** 클릭
2. 이메일/이름/주소 등 입력
3. **결제 정보(신용/체크카드 등록)** 입력
   - ⚠️ 인증 목적이며 **Always Free 한도 내에서는 청구되지 않습니다**.
   - 카드 인증 시 1 USD 정도 임시 결제 후 즉시 환불됩니다.
4. **홈 리전(Home Region) 선택**
   - 한국 사용자는 **Korea Central (Seoul)** = `ap-seoul-1` 권장
   - ⚠️ **홈 리전은 가입 후 절대 변경할 수 없습니다.**
5. SMS / 이메일 인증 → 가입 완료
6. 콘솔 접속: https://cloud.oracle.com

> ⏱️ 가입 직후 계정 활성화에 보통 5-15 분 걸립니다. 활성화 메일 받은 뒤 STEP 1 진행.

---

## STEP 1. OCI Console 에서 API 키 만들기

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
   전부 **복사**합니다. (다음 셋업 단계에서 통째로 붙여넣습니다)

복사할 내용은 이런 형태입니다:
```
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=<path to your private keyfile> # TODO
```

> 💡 `key_file=` 라인은 그대로 두면 됩니다. `./setup.sh` 가 자동으로 절대경로로 바꿔줍니다.

이제 [빠른 시작](#빠른-시작-자동-oobe-마법사-강력-권장) 의 단계 1) 부터 이어가세요.

---

## (선택) Discord 알림 설정

Discord 채널에 진행 상황과 성공/실패 알림을 받고 싶을 때만:

1. Discord 서버 → **서버 설정(Server Settings)** → **연동(Integrations)** → **웹후크(Webhooks)**
2. **새 웹후크(New Webhook)** → 채널 선택 → **URL 복사(Copy Webhook URL)**
3. `./setup.sh` 의 [4/4] 단계에서 그대로 붙여넣기

이미 셋업이 끝났다면 `oci.env` 에서 `DISCORD_WEBHOOK=` 라인만 수정하거나
`./setup.sh` 를 다시 실행하면 됩니다.

`./doctor.sh --discord` 로 실제 발송 테스트가 가능합니다.

---

## 셋업 점검 (`./doctor.sh`)

실행 전후로 셋업 상태를 진단합니다. 검사 항목:

1. `oci.env` 파일 존재
2. `OCI_CONFIG` 경로/내용 (필수 5개 키 + `.pem` 실재 여부)
3. `OCT_FREE_AD` 설정 여부
4. SSH 공개키 존재 (없으면 첫 실행 시 자동 생성됨을 안내, 짝 개인키 위치도 표시)
5. `OCI_SUBNET_ID` (신규 계정 안내)
6. Python venv + 의존 패키지
7. **OCI 인증 (실제 read-only API 호출)**
8. Discord webhook 설정 여부 (`./doctor.sh --discord` 로 실제 전송 테스트)

요약 줄에서 `[FAIL] 0` 이면 다음 단계로 진행 OK.

---

## 중지 / 재개

| 작업 | 명령 |
|---|---|
| 백그라운드 프로세스 종료 | `./stop.sh` (PID 파일 우선, 없으면 `pgrep` 폴백, 5초 graceful → SIGKILL) |
| 다시 실행 (의존성 재설치 안 함) | `./setup_init.sh rerun` |

---

## 만들어진 후 동작 / 결과 파일

- **자리 없음**: 90초 후 자동 재시도 (Discord 로 10회마다 진행 상황 알림)
- **자리 났음**: 인스턴스 생성 + Discord 성공 알림 + `INSTANCE_CREATED` 파일 생성
- **에러 발생**: `ERROR_IN_CONFIG.log` 또는 `setup_init.log` 에 사유 기록

| 파일 | 용도 |
|------|------|
| `setup_init.log` | Python 의 모든 출력 (예외 메시지 포함) |
| `launch_instance.log` | OCI API 호출 + 재시도 기록 |
| `setup_and_info.log` | 시작 시점 설정값 |
| `ERROR_IN_CONFIG.log` | 설정 오류 사유 (정상 동작 시 자동 삭제) |
| `INSTANCE_CREATED` | 생성된 인스턴스 정보 (공용 IP 포함) |
| `.main.pid` | 백그라운드 main.py PID (`stop.sh` 가 사용) |

---

## 자주 발생하는 문제

### "Out of host capacity" 가 계속 나와요

**정상입니다.** ARM 무료 자원은 매우 부족해서 수 시간 ~ 며칠 걸릴 수 있습니다.
- 한국 리전 둘 다(`ap-seoul-1,ap-chuncheon-1`) 시도하면 확률이 높아집니다 (기본값).
- Discord 알림이 설정돼있으면 진행 상황이 자동으로 옵니다.
- 컴퓨터를 계속 켜둬야 합니다 (꺼두면 시도 중단).

### `ERROR_IN_CONFIG.log` 가 생겼어요

먼저 `./doctor.sh` 부터:
```bash
./doctor.sh
cat ERROR_IN_CONFIG.log   # 실제 메시지
```

가장 흔한 원인 4가지:

| 메시지 | 원인 | 해결 |
|--------|------|------|
| `OCI_CONFIG 가 비어있습니다` | `oci.env` 가 없거나 깨짐 | `./setup.sh` 다시 실행 |
| `파일을 찾을 수 없습니다` | `.pem` 경로 오타 / 이동 누락 | `./setup.sh` 다시 실행 |
| `[DEFAULT] 의 user= 항목이 없습니다` | OCI Config 내용 비어있음 | STEP 1-2 의 미리보기 다시 복사 후 `./setup.sh` |
| `값에 공백이 포함돼 있습니다` | 줄 끝/값에 공백 | `oci.env` 직접 편집해 공백 제거 |

### Discord 알림이 안 와요

```bash
./doctor.sh --discord   # 실제 webhook 테스트 메시지 발송
```

### OCI 인증 실패

`./setup.sh` 가 셋업 직후 인증을 검증합니다. 실패 시 다음을 확인:
- `oci_config` 의 `user` / `fingerprint` / `tenancy` / `region` 가 OCI Console 미리보기와 일치하는가
- `oci_api_private_key.pem` 이 OCI Console 에 등록한 공개키와 짝인가
- 시간이 오래 지났다면 키가 만료/삭제되지 않았는가

---

## SSH 키 (자동 생성)

`./setup.sh` 또는 첫 `./setup_init.sh` 실행 시, 공개키 파일이 없으면 RSA 2048 키쌍을
자동 생성합니다.

기본 경로:
- 공개키: `~/.ssh/oci_auto.pub`
- 개인키: `~/.ssh/oci_auto`  ← **인스턴스 SSH 접속 시 사용**

> 💡 `oci.env` 의 `SSH_AUTHORIZED_KEYS_FILE` 가 비어있어도 위 경로로 자동 폴백합니다.

본인 SSH 키를 쓰고 싶다면 `oci.env` 에서 `SSH_AUTHORIZED_KEYS_FILE` 만 본인 공개키
경로(`.pub`)로 바꾸면 됩니다.

규칙: `SSH_AUTHORIZED_KEYS_FILE` 가 `*.pub` 인 경우 짝 개인키는 같은 디렉토리의 동일
이름(확장자 없음). 그 외에는 `<stem>_private` 접미사를 사용합니다.

---

## 부록 A. 수동 셋업 (마법사를 안 쓰고 싶을 때)

`./setup.sh` 를 안 쓰고 직접 파일을 다루고 싶을 때만 참고하세요.

### A-1. `.pem` 수동 이동

```bash
ls -lt ~/Downloads/*.pem
mv ~/Downloads/<파일명>.pem ./oci_api_private_key.pem
chmod 600 ./oci_api_private_key.pem
```
> ⚠️ `mv ~/Downloads/*.pem` 처럼 와일드카드 X. 다른 `.pem` 이 사라질 수 있음.

### A-2. `oci_config` 수동 작성

```bash
pwd                # 출력 예: /Users/me/automate-oracle-instance
nano oci_config
```
- STEP 1-2 미리보기 내용 붙여넣기
- 마지막 `key_file=` 라인을 절대경로로 수정:
  ```
  key_file=/Users/me/automate-oracle-instance/oci_api_private_key.pem
  ```
- 저장: `Ctrl + O` → `Enter` → `Ctrl + X`

### A-3. `oci.env` 수동 작성

옵션 ①: 단순 마법사
```bash
./setup_env.sh
```

옵션 ②: 직접 편집
```bash
cp oci.env.example oci.env
nano oci.env
```

채워야 할 항목 (대부분 기본값 OK):

| 변수 | 기본값 | 채워야 할 때 |
|------|--------|--------------|
| `OCI_CONFIG` | `./oci_config` | A-2 그대로 두면 OK. `~/.oci/config` 사용 시 변경 |
| `OCT_FREE_AD` | `AD-1` | 다른 AD 면 [부록 B](#부록-b-가용-도메인ad-수동-확인) |
| `SSH_AUTHORIZED_KEYS_FILE` | `~/.ssh/oci_auto.pub` | 비워둬도 OK (자동 폴백). 본인 키 쓰려면 경로 변경 |
| `OCI_SUBNET_ID` | (비어있음) | [부록 C](#부록-c-vcnsubnet-수동-확인) 따라 OCID 입력 권장 |
| `DISCORD_WEBHOOK` | (비어있음) | 알림 받을 때만 |

---

## 부록 B. 가용 도메인(AD) 수동 확인

`./setup.sh` 가 자동 탐지하지만, 수동으로 확인하려면:

1. OCI Console 좌측 햄버거 → **컴퓨트(Compute)** → **인스턴스(Instances)**
2. **인스턴스 생성(Create Instance)** 클릭 (실제 생성 X)
3. **셰이프 변경(Change shape)** → **VM.Standard.A1.Flex** 선택
4. **배치(Placement)** 항목에서 **"항상 무료 적격(Always Free Eligible)"** 라벨이 붙은 AD 번호 확인
5. 취소(Cancel)

> 💡 서울 리전은 `AD-1` 만 존재합니다. 미국 일부 리전은 AD 가 3개라 정확히 확인 필요.

---

## 부록 C. VCN/Subnet 수동 확인

`./setup.sh` 가 자동 탐색/생성하지만, OCID 를 직접 지정하려면:

### 옵션 1. 기존 VCN 이 있는 경우

1. OCI Console → **네트워킹(Networking)** → **가상 클라우드 네트워크**
2. VCN 클릭 → **서브넷(Subnets)** → **공용 서브넷(Public Subnet)** 클릭
3. 페이지 상단 **OCID** 옆 **복사(Copy)** 버튼 클릭

### 옵션 2. 새로 만들기

1. OCI Console → **네트워킹** → **가상 클라우드 네트워크**
2. **VCN 마법사 시작(Start VCN Wizard)** → **인터넷 연결성을 가진 VCN 생성**
3. 이름 입력 → 기본값으로 생성

`oci.env` 의 `OCI_SUBNET_ID=` 에 복사한 값을 붙여넣기.

> 💡 멀티 리전(`ap-seoul-1,ap-chuncheon-1` 등)을 쓰려면 각 리전마다 VCN/Subnet 이
> 있어야 합니다. `oci.env` 에는 한 OCID 만 적을 수 있어 다른 리전은 자동 탐색에 의존.

### (멀티 리전) 리전 구독

홈 리전 외 다른 리전을 사용하려면 먼저 구독해야 합니다:

1. OCI Console **우측 상단 리전 드롭다운** → **리전 관리(Manage Regions)**
2. 사용할 리전의 **구독(Subscribe)** 버튼 클릭 → 1-2분 대기
3. 활성화 후 우측 상단 드롭다운에서 전환 가능

---

## 부록 D. 도구 설치 안내

### git
- **macOS**: `git --version` 실행 시 Xcode CLT 설치 안내 자동 출력 → 설치
- **Ubuntu/Debian/WSL**: `sudo apt update && sudo apt install -y git`
- **CentOS/RHEL**: `sudo dnf install -y git`

### Python 3 (3.10 이상 권장)
- **macOS**: `brew install python@3.12` (Homebrew 필요)
- **Ubuntu/WSL**: `sudo apt install -y python3 python3-venv`

---

## 부록 E. `~/.oci/config` 표준 위치 사용

기존에 OCI CLI 를 쓰고 있어서 표준 위치를 선호한다면:

```bash
mkdir -p ~/.oci
mv ~/Downloads/<파일명>.pem ~/.oci/oci_api_private_key.pem
chmod 600 ~/.oci/oci_api_private_key.pem
nano ~/.oci/config   # 미리보기 붙여넣기 + key_file=/Users/me/.oci/oci_api_private_key.pem
```

`oci.env` 에서:
```
OCI_CONFIG=~/.oci/config
```

> ⚠️ 이 경우 `./setup.sh` 의 [2/4] 자동 치환은 사용할 수 없습니다.

---

## 환경변수 빠른 참조 (`oci.env`)

### 필수 항목 (대부분 기본값 OK)

| 변수 | 기본값 | 채워야 할 때 |
|------|--------|--------------|
| `OCI_CONFIG` | `./oci_config` | 표준 위치 쓰려면 `~/.oci/config` |
| `OCT_FREE_AD` | `AD-1` | 다른 AD ([부록 B](#부록-b-가용-도메인ad-수동-확인)) |
| `SSH_AUTHORIZED_KEYS_FILE` | `~/.ssh/oci_auto.pub` | 비워도 자동 폴백. 본인 키 쓰려면 변경 |

### 선택 항목

| 변수 | 무엇인가요? | 어디서 얻나요? / 기본값 |
|------|------------|----------------------|
| `OCI_REGIONS` | 시도할 리전(쉼표 구분) | OCI Console 우측 상단. 홈 리전 외엔 [부록 C](#멀티-리전-리전-구독) 의 구독 필요. 예) `ap-seoul-1,ap-chuncheon-1` |
| `DISPLAY_NAME` | 인스턴스 이름 | 자유. 기본값 `a1-free-arm` |
| `OCI_COMPUTE_SHAPE` | 서버 종류 | `VM.Standard.A1.Flex` (ARM 권장) 또는 `VM.Standard.E2.1.Micro` |
| `SECOND_MICRO_INSTANCE` | 2번째 Micro 만들 때만 `True` | `False` |
| `REQUEST_WAIT_TIME_SECS` | 재시도 간격(초) | 권장 `90` (60 미만은 OCI 차단 위험) |
| `OCI_SUBNET_ID` | 서브넷 OCID | `./setup.sh` 가 자동 탐색/생성. 수동은 [부록 C](#부록-c-vcnsubnet-수동-확인) |
| `OCI_IMAGE_ID` | 특정 이미지 OCID | 비우면 OS+버전 자동 탐색 |
| `OPERATING_SYSTEM` ⚠️ | OS 이름 | `Canonical Ubuntu` (기본) -- `OCI_IMAGE_ID` 비울 때 정확해야 함 |
| `OS_VERSION` ⚠️ | OS 버전 | `24.04` (기본) -- `OCI_IMAGE_ID` 비울 때 정확해야 함 |
| `ASSIGN_PUBLIC_IP` | 공용 IP 자동 할당 | `true` 또는 `false` |
| `BOOT_VOLUME_SIZE` | 부트 디스크 GB (최소 50) | `50` |
| `DISCORD_WEBHOOK` | Discord 알림 URL | (선택) |

> 💡 모르는 항목은 비워두거나 기본값을 그대로 사용하면 됩니다.
> ⚠️ 표시 항목은 "조건부 필수" -- 다른 값(`OCI_IMAGE_ID`)이 비어있을 때 정확해야 함.

---

## 라이선스

MIT License -- [mohankumarpaluru/oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) 기반
