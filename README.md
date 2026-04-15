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

### 1. OCI API 설정

```bash
# API Private Key 저장
vi oci_api_private_key.pem   # Private Key 내용 붙여넣기

# OCI Config 파일 생성 (sample_oci_config 참고)
vi oci_config
```

`oci_config` 예시:
```ini
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:xx:...
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=/absolute/path/to/oci_api_private_key.pem
```

### 2. 환경변수 설정

대화형 설정:
```bash
./setup_env.sh
```

또는 직접 편집:
```bash
cp oci.env.example oci.env
vi oci.env
```

### 3. 실행

```bash
./setup_init.sh
```

재실행 (의존성 설치 건너뜀):
```bash
./setup_init.sh rerun
```

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
| `launch_instance.log` | 인스턴스 생성 API 호출 로그 |
| `setup_and_info.log` | 파라미터 및 설정 정보 |
| `ERROR_IN_CONFIG.log` | OCI Config 오류 |
| `INSTANCE_CREATED` | 생성된 인스턴스 정보 |

## 알림

- **Discord**: 10회 재시도마다 진행 상황 + 성공/실패 알림
- **Telegram**: 스크립트 시작/종료/에러 알림
- **Gmail**: 성공 시 인스턴스 상세 정보 이메일 발송

## License

MIT License - [mohankumarpaluru/oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation) 기반
