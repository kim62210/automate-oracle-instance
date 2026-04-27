# 부트스트랩 인스톨러

비개발자도 더블클릭 한 번 / 명령 한 줄로 `git clone` + 의존성 설치 + `./setup.sh` 까지 자동 실행할 수 있는 진입점들입니다.

## 구조

```
installers/
├── windows/
│   ├── OciFreeArm.cmd        # 더블클릭 진입점 (PowerShell 신뢰 우회)
│   └── install.ps1           # 실제 로직 (WSL 감지/안내, 의존성, clone, setup.sh 호출)
└── macos/
    ├── OciFreeArm.command    # 더블클릭 진입점 (Finder 에서 더블클릭)
    └── install.sh            # 실제 로직 (brew/git/python 확인, clone, setup.sh 호출)
```

## 사용 방법

### Windows (WSL 필요)

#### 옵션 1: PowerShell 한 줄 (가장 간단)

PowerShell 을 열고 다음 명령을 붙여넣기:
```powershell
iwr -useb https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/windows/install.ps1 | iex
```

#### 옵션 2: 더블클릭

1. 이 디렉토리의 `windows/` 폴더를 통째로 다운로드 (또는 GitHub Release zip)
2. `OciFreeArm.cmd` 더블클릭
3. PowerShell 창이 뜨면 안내에 따라 진행

### macOS

#### 옵션 1: 터미널 한 줄 (가장 간단)

터미널을 열고 다음 명령을 붙여넣기:
```bash
curl -fsSL https://raw.githubusercontent.com/kim62210/automate-oracle-instance/main/installers/macos/install.sh | bash
```

#### 옵션 2: 더블클릭

1. 이 디렉토리의 `macos/` 폴더를 다운로드
2. (필요 시) 권한 부여:
   ```bash
   chmod +x OciFreeArm.command install.sh
   ```
3. `OciFreeArm.command` 우클릭 → **열기** → "확인되지 않은 개발자" 경고가 뜨면 **열기** 클릭

## 인스톨러가 하는 일

| 단계 | Windows (`install.ps1`) | macOS (`install.sh`) |
|---|---|---|
| 1 | WSL 설치 여부 확인. 없으면 안내 메시지 후 종료 (자동 install 안 함, 관리자 권한 + 재부팅 회피) | git/python3 확인. 없으면 `brew install`. brew 없으면 안내 |
| 2 | 디폴트 WSL 배포판 확인 | -- |
| 3 | WSL 안에서 `apt install -y git python3 python3-venv` (필요 시) | -- |
| 4 | `~/automate-oracle-instance` 에 clone (있으면 `git pull`) | `~/automate-oracle-instance` 에 clone (있으면 `git pull`) |
| 5 | WSL 안에서 `./setup.sh` 인터랙티브 실행 (4-입력 마법사) | `./setup.sh` 인터랙티브 실행 |
| 6 | `./setup_init.sh` 실행 (백그라운드 인스턴스 생성 시작) | `./setup_init.sh` 실행 |

## 인스톨러 후 사용

설치가 끝나면 이후 명령은 모두 레포 디렉토리에서 실행:

**Windows (WSL 콘솔)**
```bash
wsl
cd ~/automate-oracle-instance
./doctor.sh           # 셋업 진단
./stop.sh             # 백그라운드 종료
cat INSTANCE_CREATED  # 생성된 인스턴스 정보
```

**macOS (터미널)**
```bash
cd ~/automate-oracle-instance
./doctor.sh
./stop.sh
cat INSTANCE_CREATED
```

## 트러블슈팅

### Windows: `wsl --install` 실패

- 관리자 권한으로 PowerShell 실행했는지 확인
- 윈도우 버전이 Windows 10 21H2+ / Windows 11 인지 확인
- BIOS 에서 가상화(VT-x / AMD-V) 활성화되어 있어야 함
- 공식 가이드: https://learn.microsoft.com/ko-kr/windows/wsl/install

### Windows: 인스톨러 실행 시 "스크립트가 비활성화되어 있습니다" 오류

`OciFreeArm.cmd` 가 PowerShell 신뢰 우회(`-ExecutionPolicy Bypass`)로 실행하므로 일반적으로는 발생하지 않습니다.
직접 `install.ps1` 을 호출했다면 `OciFreeArm.cmd` 더블클릭 또는 PowerShell 에서:
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1
```

### macOS: "확인되지 않은 개발자" 경고

코드 서명을 하지 않았기 때문에 정상입니다.
`OciFreeArm.command` 를 **우클릭 → 열기** → 경고 다이얼로그에서 **열기** 클릭하면 한 번만 확인하면 그 다음부턴 경고 없이 동작합니다.

또는 터미널 one-liner (`curl ... | bash`) 방식을 사용하면 경고 없음.

### 인스톨러가 도중에 멈췄어요

직접 다시 실행하거나, 기존 진행 상황을 살리기 위해 레포 디렉토리에서:
```bash
cd ~/automate-oracle-instance
./doctor.sh           # 어디까지 됐는지 확인
./setup.sh            # 마법사 다시 실행 (oci.env 백업 후 재생성)
./setup_init.sh rerun # 의존성 재설치 없이 인스턴스 생성 재개
```
