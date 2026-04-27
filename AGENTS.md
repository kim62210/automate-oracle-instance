# AGENTS.md

이 레포에서 AI 에이전트(Claude Code, Codex CLI, Cursor, Copilot, 또는 임의 LLM + 브라우저 자동화 도구)가 사용자를 대신해 처리할 수 있는 작업과, 절대 해서는 안 되는 작업을 한 페이지로 정리합니다.

> 이 문서는 사람과 에이전트 모두를 독자로 가정합니다. 에이전트는 작업 시작 전 반드시 이 파일을 먼저 읽고, 필요한 세부 가이드는 [`docs/agent/`](docs/agent/) 에서 참조하세요.

---

## 프로젝트 한 줄 요약

오라클 클라우드 Free Tier ARM 인스턴스(VM.Standard.A1.Flex / 4 OCPU / 24GB RAM / 평생 무료)를 "Out of host capacity" 상태에서도 자리가 날 때까지 자동으로 재시도하여 생성하는 셸+Python 도구.

---

## 에이전트가 사용자를 대신해 처리해도 되는 작업

| # | 작업 | 자동화 방법 | 참조 |
|---|---|---|---|
| 1 | OCI Console 에서 API 키 추가, 개인키(.pem) 다운로드, "구성 파일 미리보기" 텍스트 복사 | 브라우저 컨트롤러 (Playwright / Chrome DevTools / Puppeteer / Selenium) | [docs/agent/oci-onboarding.md](docs/agent/oci-onboarding.md) |
| 2 | (선택) 멀티 리전 구독, VCN/Subnet 생성 후 OCID 복사 | 위와 동일. 단 인스톨러가 자동 생성도 지원하므로 우선순위 낮음 | [docs/agent/oci-onboarding.md](docs/agent/oci-onboarding.md) |
| 3 | 부트스트랩 인스톨러 실행 (`curl … \| bash` / `iwr … \| iex`) | 셸 명령 한 줄 실행 | [docs/agent/local-execution.md](docs/agent/local-execution.md) |
| 4 | `./setup.sh` 4-입력 마법사의 stdin 자동 채움 | here-doc / pipe / pty 자동화 | [docs/agent/local-execution.md](docs/agent/local-execution.md) |
| 5 | 인스턴스 생성 진행 모니터링 (`launch_instance.log`, `INSTANCE_CREATED`, Discord webhook 응답 등) | 파일 tail + 폴링 | [docs/agent/local-execution.md](docs/agent/local-execution.md) |
| 6 | 셋업 진단 (`./doctor.sh`) 결과 해석 + 자동 회복 | 출력 파싱 + 재실행 | [docs/agent/local-execution.md](docs/agent/local-execution.md) |
| 7 | 백그라운드 종료 (`./stop.sh`) | 셸 명령 | [docs/agent/local-execution.md](docs/agent/local-execution.md) |

---

## 에이전트가 절대 하면 안 되는 작업 (보안)

| # | 금지 | 사유 |
|---|---|---|
| 1 | OCI 계정 비밀번호 / 2FA 코드 입력 | 사용자가 직접 로그인 후 세션을 에이전트에게 인계해야 함. 에이전트가 자격증명을 다루지 않는다 |
| 2 | `.pem` 파일 내용을 LLM 컨텍스트에 인용 / 채팅에 표시 / 로그에 기록 | 인스턴스 SSH 접속 권한이 새는 것과 동등 |
| 3 | OCI `fingerprint` / `tenancy` / `user` OCID 전체값을 채팅 메시지/PR 본문에 평문 노출 | 식별정보 + 부분 인증재료. 마스킹 필수 (앞 10자 + `...`) |
| 4 | Discord Webhook URL 평문 노출 | 알림 채널 하이재킹 가능 |
| 5 | `oci.env`, `oci_config`, `oci_api_private_key.pem` 파일을 git 에 commit | `.gitignore` 가 차단하지만 의도적으로 -f 추가 금지 |
| 6 | `git push --force` / `branch -D` / `wsl --unregister` 등 파괴적 명령을 사용자 명시 없이 실행 | 작업 손실 위험 |
| 7 | 인스턴스 생성 후 OCI 콘솔에서 임의로 인스턴스 삭제, 비밀번호 변경 등 계정 상태 변경 | 사용자 의도 외 부작용 |

자세한 정책은 [docs/agent/secrets-handling.md](docs/agent/secrets-handling.md) 참조.

---

## 표준 진행 흐름 (에이전트가 따를 시퀀스)

```
[사용자] OCI 가입 + 브라우저에서 https://cloud.oracle.com 로그인 (2FA 포함)
   ↓
[에이전트] 사용자 세션을 인계받아 (브라우저 컨트롤러 부착):
   ├─ docs/agent/oci-onboarding.md  Step 1: API 키 추가 + .pem 다운 + 미리보기 클립보드
   └─ (선택) Step 2~3: VCN/Subnet 또는 멀티 리전 구독
   ↓
[에이전트] 터미널에서:
   ├─ docs/agent/local-execution.md  의 인스톨러 one-liner 실행
   ├─ ./setup.sh 4-입력 자동 채움 (.pem 경로, 미리보기 텍스트, 서브넷 옵션, Discord URL)
   └─ ./setup_init.sh 실행 → 백그라운드 모니터링
   ↓
[에이전트] INSTANCE_CREATED 또는 ERROR_IN_CONFIG.log 감지 → 사용자에게 보고
```

---

## 사용자 동의가 필요한 시점

에이전트는 다음 시점에 **반드시 사용자 명시 동의**를 받아야 합니다:

1. **첫 브라우저 컨트롤 시작** — 어떤 도메인(cloud.oracle.com)에 접근하는지 알리기
2. **`.pem` 파일 이동/복사** — 어디에서 어디로 옮기는지
3. **`./setup_init.sh` 실행 (백그라운드 시작)** — 종료 시점 / 비용 영향 안내
4. **OCI VCN 자동 생성** — 신규 네트워크 자원 생성. Free Tier 한도 내이지만 사용자 자원 변경
5. **Discord Webhook URL 입력** — URL 출처 확인

---

## 브라우저 자동화 도구 매핑 (참고)

| 에이전트 | 추천 브라우저 도구 |
|---|---|
| Claude Code | `chrome-devtools` MCP 서버 또는 `playwright` MCP |
| Codex CLI | Playwright + Codex 의 셸 실행 |
| Cursor / VS Code Copilot | Playwright 셸 호출 |
| 범용 (LLM-agnostic) | Playwright Python/Node API + LLM 의 자연어 명령 |

OCI Console UI 는 자주 변경되므로 **CSS selector 하드코딩보다 자연어 + role/aria-label 기반 탐색을 권장**합니다 (예: `getByRole('button', { name: /API 키 추가|Add API Key/i })`).

---

## 추가 참조

- [docs/agent/oci-onboarding.md](docs/agent/oci-onboarding.md) — OCI Console 단계별 시나리오 (한/영 라벨, selector hint, 실패 폴백)
- [docs/agent/local-execution.md](docs/agent/local-execution.md) — 인스톨러/마법사 stdin 자동화, 모니터링, 회복
- [docs/agent/secrets-handling.md](docs/agent/secrets-handling.md) — 민감 데이터 처리 정책
- [README.md](README.md) — 사람 사용자 빠른 시작
- [installers/README.md](installers/README.md) — 부트스트랩 인스톨러 동작 상세
