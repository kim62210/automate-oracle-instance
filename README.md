# OCI Free Tier ARM Instance Auto-Creator

Oracle Cloud Free Tier ARM 인스턴스(VM.Standard.A1.Flex) 자동 생성 스크립트.

"Out of host capacity" 에러를 자동 재시도로 우회하여, 리소스가 풀리는 즉시 인스턴스를 생성한다.

## 스펙

| 항목 | Free Tier ARM | Free Tier AMD |
|------|--------------|---------------|
| Shape | VM.Standard.A1.Flex | VM.Standard.E2.1.Micro |
| OCPU | 4 | 1 |
| RAM | 24 GB | 1 GB |

## 사전 준비

1. **OCI API Key** - [Oracle API Key 생성 가이드](https://docs.oracle.com/en-us/iaas/Content/API/Concepts/apisigningkey.htm)
   - OCI Console > Profile > API Keys > Add API Key
   - Private Key 파일(`oci_api_private_key.pem`)과 Config 정보를 저장
2. **가용 도메인(AD) 확인** - 인스턴스 생성 화면에서 Always Free 대상 AD 확인
3. **(선택) 알림 설정** - Discord Webhook / Telegram Bot / Gmail App Password

## 설치 및 실행

```bash
git clone https://github.com/kim62210/automate-oracle-instance.git
cd automate-oracle-instance
```

### 1. OCI API Config 파일 준비

OCI Console > Profile > **API Keys > Add API Key** 에서 키를 생성하면 우측에
config 미리보기가 표시된다. 이 내용을 그대로 파일로 저장한다.

옵션 A. **OCI CLI 표준 위치 사용 (권장)**
```bash
mkdir -p ~/.oci
vi ~/.oci/config                  # API Key 생성 화면의 Config 내용 붙여넣기
vi ~/.oci/oci_api_private_key.pem # Private Key (.pem) 내용 붙여넣기
chmod 600 ~/.oci/oci_api_private_key.pem
```

옵션 B. **레포 디렉토리 안에 보관**
```bash
vi oci_config                     # sample_oci_config 참고
vi oci_api_private_key.pem
```

`oci_config` 예시 (`sample_oci_config` 와 동일 형식):
```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:xx:...
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=/absolute/path/to/oci_api_private_key.pem
```

> [!IMPORTANT]
> `key_file` 은 **반드시 절대 경로**로 적는다. `~` 확장은 동작하지 않는다.

### 2. 환경변수 (`oci.env`) 설정

먼저 템플릿을 복사한다 (이 단계를 건너뛰면 `ERROR_IN_CONFIG.log` 가 생성된다):
```bash
cp oci.env.example oci.env
```

옵션 A. **대화형 생성**
```bash
./setup_env.sh
```

옵션 B. **직접 편집**
```bash
vi oci.env
```

최소 설정 예시:
```bash
OCI_CONFIG=/Users/your_id/.oci/config   # 1단계에서 만든 파일의 절대 경로
OCT_FREE_AD=AD-1
OCI_REGIONS=ap-seoul-1,ap-chuncheon-1
SSH_AUTHORIZED_KEYS_FILE=/Users/your_id/.ssh/id_ed25519_oci.pub
```

### 3. 실행

```bash
./setup_init.sh
```

재실행 (의존성 설치 건너뜀):
```bash
./setup_init.sh rerun
```

정상 시작되면 `setup_init.log`, `launch_instance.log`, `setup_and_info.log`
세 가지 로그가 생성된다.

## 환경변수 (oci.env)

### 필수

| 변수 | 설명 |
|------|------|
| `OCI_CONFIG` | OCI API Config 파일 절대 경로 |
| `OCT_FREE_AD` | Always Free 가용 도메인 (예: AD-1) |

### 선택

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `OCI_REGIONS` | config의 region | 쉼표 구분 리전 목록, 순환 시도 |
| `DISPLAY_NAME` | - | 인스턴스 이름 |
| `OCI_COMPUTE_SHAPE` | VM.Standard.A1.Flex | 셰이프 (ARM 또는 AMD) |
| `REQUEST_WAIT_TIME_SECS` | 60 | 재시도 간격 (초) |
| `SSH_AUTHORIZED_KEYS_FILE` | - | SSH 공개키 경로 (없으면 자동 생성) |
| `OCI_SUBNET_ID` | - | 서브넷 OCID (로컬 실행 시 필수) |
| `OCI_IMAGE_ID` | - | 이미지 OCID (비워두면 OS/버전으로 자동 탐색) |
| `OPERATING_SYSTEM` | - | OS 이름 (예: Canonical Ubuntu) |
| `OS_VERSION` | - | OS 버전 (예: 24.04) |
| `ASSIGN_PUBLIC_IP` | false | 공용 IP 자동 할당 |
| `BOOT_VOLUME_SIZE` | 50 | 부트 볼륨 크기 (GB, 최소 50) |
| `NOTIFY_EMAIL` | False | Gmail 알림 활성화 |
| `EMAIL` | - | Gmail 주소 (발신/수신 동일) |
| `EMAIL_PASSWORD` | - | Gmail 앱 비밀번호 |
| `DISCORD_WEBHOOK` | - | Discord 웹훅 URL |
| `TELEGRAM_TOKEN` | - | Telegram 봇 토큰 |
| `TELEGRAM_USER_ID` | - | Telegram 사용자 ID |

## 동작 흐름

```
1. OCI API 인증 및 리전 타겟 설정
2. 지정된 리전을 순환하며 인스턴스 생성 시도
3. "Out of host capacity" -> REQUEST_WAIT_TIME_SECS 후 재시도
4. 성공 시 INSTANCE_CREATED 파일 생성 + 알림 발송
```

## 로그 파일

| 파일 | 내용 |
|------|------|
| `setup_init.log` | `main.py` 의 stdout/stderr (예외 trace 포함) |
| `launch_instance.log` | 인스턴스 생성 API 호출 + 재시도 로그 |
| `setup_and_info.log` | 파라미터 및 설정 정보 |
| `ERROR_IN_CONFIG.log` | OCI Config 검증 실패 사유 (정상 시 자동 삭제) |
| `INSTANCE_CREATED` | 생성된 인스턴스 정보 |

## 트러블슈팅

### `ERROR_IN_CONFIG.log` 가 생성되며 셋업이 멈춤

`main.py` 가 OCI Config 검증에 실패하면 사유를 로그 파일에 기록하고
즉시 종료한다. `setup_init.sh` 가 이를 감지해 셋업을 중단한다.

대표 원인과 진단 명령:

| 메시지 | 원인 | 해결 |
|--------|------|------|
| `OCI_CONFIG 가 비어있습니다` | `oci.env` 미생성 | `cp oci.env.example oci.env` 후 `OCI_CONFIG` 채우기 |
| `파일을 찾을 수 없습니다` | 경로 오타 / 상대 경로 | 절대 경로로 수정, `ls -la` 로 존재 확인 |
| `[DEFAULT] 의 user= 항목이 없습니다` | OCI Config 내용 누락 | `sample_oci_config` 참고해 user/fingerprint/tenancy/region/key_file 채우기 |
| `값에 공백이 포함돼 있습니다` | 따옴표 / 공백 문자 | 값 양옆 공백 제거, 따옴표 사용 금지 |

진단 체크리스트:
```bash
ls -la oci.env                                                    # 1) 파일 존재
grep "^OCI_CONFIG=" oci.env                                       # 2) 경로 확인
cat "$(grep '^OCI_CONFIG=' oci.env | cut -d= -f2)"                # 3) Config 내용
cat ERROR_IN_CONFIG.log                                           # 4) 실제 사유
```

### `setup_init.log` 에서 Python 예외 확인

이전 버전은 `nohup ... > /dev/null 2>&1` 으로 stderr 가 모두 사라졌었다.
현재 버전은 모든 출력이 `setup_init.log` 에 기록된다.
```bash
tail -f setup_init.log
```

### 셋업은 됐지만 계속 `Out of host capacity` 만 나옴

정상 동작이다. Free Tier ARM 자원은 매우 부족해 수 시간~수 일이 걸릴 수 있다.
`OCI_REGIONS=ap-seoul-1,ap-chuncheon-1` 처럼 멀티 리전을 지정하면 순환 시도하며
Discord/Telegram 알림으로 10회마다 진행 상황이 전송된다.

## 알림

- **Discord**: 10회 재시도마다 진행 상황 + 성공/실패 알림
- **Telegram**: 스크립트 시작/종료/에러 알림
- **Gmail**: 성공 시 인스턴스 상세 정보 이메일 발송

## License

MIT License - [mohankumarpaluru/oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) 기반
