# docs/agent/oci-onboarding.md — OCI Console 자동화 시나리오

브라우저 컨트롤러(Playwright / Chrome DevTools / Puppeteer / Selenium 등)를 가진 AI 에이전트가 사용자 OCI Console 작업을 대신 진행할 때 따를 단계별 시나리오입니다.

> ⚠️ **사전 조건**: 사용자가 직접 https://cloud.oracle.com 에 로그인 완료 (이메일 + 비밀번호 + 2FA). 에이전트는 로그인된 세션을 인계받습니다. **에이전트가 비밀번호/2FA 를 입력하지 않습니다.**

> ⚠️ OCI Console UI 는 자주 변경됩니다. 아래 selector hint 는 참고용이며, **자연어 + role/aria-label 기반 탐색**을 우선하세요.

---

## 0. 도구 능력 점검 (에이전트 준비)

작업 시작 전 다음을 확인:

- [ ] 사용자가 명시적으로 "OCI Console 작업 자동 진행"을 허가했는가?
- [ ] 브라우저 컨트롤러가 다음 동작 가능한가:
  - DOM 조회 (`role`, `aria-label`, `text` 기반)
  - 클릭 / 텍스트 입력
  - 페이지 텍스트 읽기 (스크린리더 트리)
  - 다운로드 가로채기 또는 다운로드 폴더 모니터링
  - 클립보드 읽기 (또는 `navigator.clipboard.readText` 권한 우회)
- [ ] 사용자 OCI 홈 리전을 사전 확인했는가? (URL 의 `region=` 파라미터)

---

## STEP 1. API 키 추가 + 개인키 다운로드 + 구성 파일 미리보기 복사

가장 핵심 단계. 결과물 두 가지: `.pem` 파일 + 미리보기 텍스트 (클립보드 또는 stdin).

### 1-1. 내 프로필 진입

| 동작 | 자연어 지시 | selector hint (예시, 변경 가능) |
|---|---|---|
| 우측 상단 사람 아이콘 클릭 | "Open the user profile menu in the top-right corner" | `[data-test-id="header-menu-user-button"]`, `button[aria-label*="profile" i]`, `button[aria-label*="프로필"]` |
| 메뉴에서 "내 프로필 / My Profile / User settings" 선택 | "Click 'User settings' (or '내 프로필')" | `a[href*="/identity/users/"]`, `text=/My Profile|내 프로필|User settings/i` |

**확인 신호**: URL 이 `/identity/domains/.../users/...` 형태로 변경. 페이지 제목에 사용자 이메일/이름.

**실패 폴백**:
- 메뉴 안 뜨면 → 페이지 새로고침 후 재시도 (한 번만)
- 다중 도메인 계정이면 도메인 선택 화면 → 사용자에게 도메인 선택 묻기

### 1-2. API 키 메뉴

| 동작 | 자연어 지시 | selector hint |
|---|---|---|
| 좌측 사이드바에서 "API 키" 클릭 | "In the left sidebar resources panel, click 'API Keys'" | `a[href*="api-keys"]`, `text=/API Keys?|API 키/i` |

**확인 신호**: 페이지 제목 "API Keys" 또는 "API 키", 가운데에 "API 키 추가/Add API Key" 버튼.

### 1-3. API 키 쌍 생성

| 동작 | 지시 | hint |
|---|---|---|
| "API 키 추가" 버튼 | "Click 'Add API Key'" | `button:has-text(/Add API Key|API 키 추가/i)` |
| 모달의 "API 키 쌍 생성" 라디오 선택 | "Select the radio option 'Generate API Key Pair'" | `input[type=radio][value*="GENERATE"]`, `label:has-text(/Generate API Key Pair|API 키 쌍 생성/i)` |
| "Download Private Key / 개인 키 다운로드" 버튼 | "Click 'Download Private Key' (the green button)" | `button:has-text(/Download Private Key|개인 키 다운로드/i)` |

**다운로드 처리**:
- 브라우저 다운로드 가로채기로 파일 객체를 얻거나, OS 의 `~/Downloads` 폴더 모니터링
- 파일명 패턴: `oracleidentitycloudservice_*-*.pem` 또는 임의의 `.pem`
- 다운로드 완료 신호: 파일 크기 > 1KB, 첫 줄이 `-----BEGIN PRIVATE KEY-----` 또는 `-----BEGIN RSA PRIVATE KEY-----`

> 🔒 **금지**: `.pem` 파일 내용을 채팅/로그/PR 본문에 절대 출력하지 말 것. 경로만 다룬다. ([secrets-handling.md](secrets-handling.md))

**실패 폴백**:
- 다운로드 차단(브라우저 설정) → 사용자에게 다운로드 허용 후 "API 키 추가" 버튼 다시 클릭하도록 요청
- 공개 키 직접 붙여넣기 모드만 활성화 → 에이전트가 키 쌍 로컬 생성 후 공개 키만 페이스트하는 분기 (고급, 별도 시나리오)

### 1-4. 추가 + 미리보기 복사

| 동작 | 지시 | hint |
|---|---|---|
| 모달 하단 "Add / 추가" 버튼 | "Click 'Add' to confirm" | `button:has-text(/^Add$|^추가$/)` |

**자동으로 뜨는 모달: "Configuration File Preview / 구성 파일 미리보기"**

이 모달에 다음 형태의 텍스트가 표시됨:
```
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=<path to your private keyfile> # TODO
```

| 동작 | 지시 | hint |
|---|---|---|
| 미리보기 텍스트 추출 | "Read the entire text content of the configuration preview block" | `pre`, `code`, `[role=textbox][readonly]`, `textarea[readonly]` |
| (대안) "Copy" 버튼 클릭 후 클립보드 읽기 | "Click 'Copy' button next to the preview" | `button:has-text(/Copy|복사/i)` |

**결과 검증**:
- 추출된 텍스트가 5개 라인을 모두 포함하는지: `^\[DEFAULT\]`, `^user=ocid1\.user\.`, `^fingerprint=`, `^tenancy=ocid1\.tenancy\.`, `^region=[a-z]+-[a-z]+-\d+`
- 누락 시 한 번 재시도, 그래도 누락이면 사용자에게 보고

> 🔒 **민감 데이터**: 미리보기에는 `user`, `fingerprint`, `tenancy` 같은 식별/인증재료가 들어있다. 채팅에 그대로 출력 금지. **stdin/파일 경로 형태로** 다음 단계의 `./setup.sh` 에 전달한다.

### 1-5. 모달 닫기

| 동작 | 지시 |
|---|---|
| "Close / 닫기" 버튼 | "Close the configuration preview modal" |

---

## STEP 2. (선택) VCN/Subnet 사전 생성

**이 단계는 대부분 생략 가능**합니다. 이유: `./setup.sh` 가 OCI API 로 기존 VCN/Subnet 자동 탐색 → 없으면 자동 생성하기 때문입니다. 다음 경우에만 진행:

- 사용자가 특정 컴파트먼트 / 특정 CIDR 사용을 명시
- 자동 생성이 권한 부족으로 실패한 적이 있음

### 2-1. VCN 마법사

| 동작 | 지시 | hint |
|---|---|---|
| 햄버거 메뉴 → Networking → Virtual Cloud Networks | "Open hamburger menu → Networking → Virtual Cloud Networks" | `nav button[aria-label*="menu" i]` |
| "Start VCN Wizard / VCN 마법사 시작" | "Click 'Start VCN Wizard'" | `button:has-text(/Start VCN Wizard|VCN 마법사/i)` |
| "VCN with Internet Connectivity / 인터넷 연결성을 가진 VCN 생성" | "Select 'Create VCN with Internet Connectivity'" | `input[type=radio][value*="INTERNET" i]` |
| VCN 이름 입력 | "Type 'free-tier-vcn' as the VCN name" | `input[name="vcnName" i]` 또는 라벨 매칭 |
| Next → Create | 단계별 다음 버튼 | -- |

### 2-2. Subnet OCID 추출

| 동작 | 지시 |
|---|---|
| 생성된 VCN 클릭 → Subnets 탭 → Public Subnet 클릭 | -- |
| OCID 옆 "Copy / 복사" 버튼 클릭 후 클립보드 읽기 | -- |

검증: 형식 `ocid1.subnet.oc1.<region>.aaaaaaa...`

---

## STEP 3. (선택) 멀티 리전 구독

기본 흐름은 홈 리전(`ap-seoul-1`) 만 사용. 인스턴스 생성 확률을 높이려 다른 리전(예: `ap-chuncheon-1`) 도 시도하려면 사전 구독 필요.

### 3-1. 리전 관리

| 동작 | 지시 | hint |
|---|---|---|
| 우측 상단 리전 드롭다운 | "Click the region dropdown in the top-right" | `button[aria-label*="region" i]` |
| "Manage Regions / 리전 관리" | "Click 'Manage Regions'" | `text=/Manage Regions|리전 관리/i` |
| 추가할 리전 옆 "Subscribe / 구독" | "Click 'Subscribe' next to 'Korea Central (Chuncheon)'" | row 매칭 후 button |
| 약관 동의 → Subscribe 확인 | -- | -- |

활성화까지 1-2분 대기. 활성화 안 되면 다음 단계(`./setup.sh`) 진행 시 해당 리전이 자동 skip 됨.

---

## STEP 4. 결과 검증 (에이전트 자가 점검)

다음 단계(`./setup.sh`) 로 넘어가기 전 모든 산출물이 갖춰졌는지 확인:

- [ ] `.pem` 파일이 사용자 시스템의 알려진 경로에 존재 (예: `~/Downloads/oracleidentitycloudservice_*.pem`)
- [ ] 미리보기 텍스트가 메모리/임시 파일에 보관 중 (5개 필수 키 검증 통과)
- [ ] (선택) Subnet OCID 가 클립보드/메모리에 보관 중

이 시점에서 [docs/agent/local-execution.md](local-execution.md) 의 STEP 1 (인스톨러 실행) 으로 진행.

---

## 부록 A. UI 변경 대응 — 자연어 우선 탐색

OCI Console 은 분기마다 selector 가 바뀌는 경우가 많습니다. 다음 우선순위로 탐색하세요:

1. **role + accessible name** (가장 안정적):
   - Playwright: `page.getByRole('button', { name: /Add API Key|API 키 추가/i })`
   - Selenium: `find_element(By.XPATH, "//button[contains(., 'Add API Key') or contains(., 'API 키 추가')]")`
2. **page text** (대시보드 라벨이 직관적이라 잘 안 바뀜):
   - `page.getByText(/구성 파일 미리보기|Configuration File Preview/i)`
3. **CSS selector** (마지막 수단, 자주 깨짐):
   - `[data-test-id]` > class 추정 > 속성 매칭

검색 실패 시 페이지의 accessibility tree (`page.accessibility.snapshot()`) 를 LLM 에게 보여주고 다음 클릭 위치를 자연어로 추론하게 하는 게 가장 견고합니다.

---

## 부록 B. 한국어 / 영어 라벨 매핑 (사용자 언어 설정에 따라)

| 영어 | 한국어 |
|---|---|
| User settings / My Profile | 내 프로필 / 사용자 설정 |
| API Keys | API 키 |
| Add API Key | API 키 추가 |
| Generate API Key Pair | API 키 쌍 생성 |
| Download Private Key | 개인 키 다운로드 |
| Add | 추가 |
| Configuration File Preview | 구성 파일 미리보기 |
| Copy | 복사 |
| Close | 닫기 |
| Networking | 네트워킹 |
| Virtual Cloud Networks | 가상 클라우드 네트워크 |
| Start VCN Wizard | VCN 마법사 시작 |
| Create VCN with Internet Connectivity | 인터넷 연결성을 가진 VCN 생성 |
| Subnets | 서브넷 |
| Manage Regions | 리전 관리 |
| Subscribe | 구독 |
| Always Free Eligible | 항상 무료 적격 |

OCI Console URL 의 `?lang=` 또는 `Accept-Language` 헤더로 언어 강제 가능. 가능하면 영어로 통일하면 selector 단순화.

---

## 부록 C. 시나리오 실행 의사 코드 (Playwright Python)

```python
# 의사 코드 — 실제 selector 는 OCI UI 변경 시 갱신 필요
async def oci_onboarding(page, downloads_dir):
    # 1-1
    await page.get_by_role("button", name=re.compile("profile", re.I)).click()
    await page.get_by_role("link", name=re.compile("user settings|내 프로필", re.I)).click()

    # 1-2
    await page.get_by_role("link", name=re.compile("api keys?|api 키", re.I)).click()

    # 1-3
    await page.get_by_role("button", name=re.compile("add api key|api 키 추가", re.I)).click()
    await page.get_by_label(re.compile("generate api key pair|api 키 쌍 생성", re.I)).check()

    # 다운로드 가로채기
    async with page.expect_download() as dl_info:
        await page.get_by_role("button", name=re.compile("download private key|개인 키 다운로드", re.I)).click()
    download = await dl_info.value
    pem_path = downloads_dir / download.suggested_filename
    await download.save_as(pem_path)

    # 1-4
    await page.get_by_role("button", name=re.compile("^add$|^추가$", re.I)).click()

    # 미리보기 추출
    preview = await page.get_by_role("textbox", name=re.compile("preview|미리보기", re.I)).input_value()
    if not all(k in preview for k in ["[DEFAULT]", "user=", "fingerprint=", "tenancy=", "region="]):
        raise RuntimeError("Preview missing required keys")

    return pem_path, preview  # ← 다음 단계 (local-execution.md) 로 전달
```

이 함수의 반환값을 [local-execution.md](local-execution.md) 의 `./setup.sh` stdin 자동 채움 단계에 그대로 전달합니다.
