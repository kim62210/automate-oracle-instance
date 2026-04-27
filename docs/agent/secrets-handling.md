# docs/agent/secrets-handling.md — 민감 데이터 처리 정책

이 레포에서 AI 에이전트가 다루게 되는 민감 데이터의 분류, 처리 규칙, 금지 행위를 정의합니다.

> **이 정책은 [AGENTS.md](../../AGENTS.md) 의 "에이전트가 절대 하면 안 되는 작업" 섹션의 상세 규정입니다.** 충돌이 있으면 더 보수적인 쪽을 따르세요.

---

## 1. 민감 데이터 분류

| 등급 | 종류 | 예시 |
|---|---|---|
| **L1: 절대 노출 금지** | OCI API 개인키, 인스턴스 SSH 개인키 | `oci_api_private_key.pem`, `~/.ssh/oci_auto`, 기타 `*_private`, `BEGIN PRIVATE KEY` 블록 |
| **L2: 마스킹 후 제한 노출** | OCI fingerprint, OCID, 인스턴스 ID, 공용 IP, Discord webhook URL | `xx:xx:xx:...`, `ocid1.user.oc1..aaaaa<32+chars>`, `ocid1.tenancy.oc1.<...>` |
| **L3: 일반** | 인스턴스 표시 이름, 리전 코드, AD 번호, 셰이프, OS 버전 | `a1-free-arm`, `ap-seoul-1`, `AD-1`, `VM.Standard.A1.Flex` |
| **L0: 비밀 아님 (참고)** | 공개 SSH 키 (.pub), 공식 OCI 문서 URL | `ssh-rsa AAAA...` |

---

## 2. L1 (절대 노출 금지) 규칙

### 2-1. 적용 대상

- `oci_api_private_key.pem` (레포 안)
- `~/.oci/oci_api_private_key.pem` (대체 위치)
- `~/.ssh/oci_auto` (자동 생성된 SSH 개인키)
- 사용자가 직접 만든 SSH 개인키 (`~/.ssh/id_rsa`, `~/.ssh/id_ed25519` 등)
- 위 파일 내용 = `-----BEGIN ... PRIVATE KEY-----` 으로 시작하는 모든 텍스트

### 2-2. 허용 동작

- **파일 경로** 만 다룸: `cp $PEM_PATH ./oci_api_private_key.pem`, `chmod 600`
- 권한 비트 확인: `stat -c '%a' file` / `ls -la file`
- 파일 존재 여부 / 크기 / 첫 줄(`head -1`) 의 패턴 매칭 (예: `BEGIN PRIVATE KEY` 가 있는지) — **단, 결과를 채팅에 출력 시 "valid" / "invalid" 같은 boolean 으로만**

### 2-3. 금지 동작

- ❌ 파일 내용 `cat` / `head -100` / `Read` 후 결과를 LLM 컨텍스트에 보관
- ❌ 채팅 메시지, PR 본문, 커밋 메시지, 이슈 댓글, Slack/Discord 메시지에 키 내용 인용
- ❌ 키 파일을 사용자 동의 없이 git add (.gitignore 차단되지만 `git add -f` 금지)
- ❌ 키 파일을 임시 web 서비스(pastebin, gist, transfer.sh 등) 업로드
- ❌ 키 파일을 OS 클립보드에 복사 (다른 앱이 클립보드 hooking 가능)
- ❌ 키 파일을 메모리 덤프, 코어 덤프, 스크린샷에 노출

### 2-4. 위반 시 즉시 조치

만약 실수로 노출이 발생했다면:
1. 사용자에게 즉시 알림
2. OCI Console 에서 해당 API 키 즉시 폐기
3. 인스턴스 SSH 키 노출이면 인스턴스 재생성 또는 키 교체

---

## 3. L2 (마스킹 후 제한 노출) 규칙

### 3-1. OCID 마스킹

OCID 는 부분적으로 식별 가능한 정보. 채팅/로그/PR 에 노출 시 마스킹 권장:

```
ocid1.user.oc1..aaaaaaaa1234567890abcdefghijklmnopqrstuvwxyz1234
                                                                ^^^^^^^^
                                                                보존
ocid1.user.oc1..aaaaaaaa****...****1234   ← 권장 노출 형태
```

JS 예시:
```javascript
function maskOcid(ocid) {
    if (!ocid || ocid.length < 30) return ocid;
    return ocid.slice(0, 20) + "***" + ocid.slice(-4);
}
```

### 3-2. Fingerprint 마스킹

```
xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx:xx
->
xx:xx:**:**:**:**:**:**:**:**:**:**:**:**:xx:xx
```

### 3-3. Public IP

인스턴스 공용 IP 는 마스킹 불필요(네트워크 스캔으로 발견 가능). 다만 PR/공개 이슈에는 가능한 한 노출 자제.

### 3-4. Discord Webhook URL

URL 자체가 인증재료 ([Discord 정책](https://discord.com/developers/docs/resources/webhook)). L1 수준으로 보수적 처리:

- 사용자에게서 입력받을 때 화면에 평문 표시 ❌ (입력 후 즉시 마스킹)
- 로그 / PR / 채팅에 절대 평문 X
- `oci.env` 파일에는 평문 저장 (.gitignore 보호)
- 마스킹 형태: `https://discord.com/api/webhooks/12345.../[redacted]`

### 3-5. OCI 미리보기 텍스트

`[oci-onboarding.md](oci-onboarding.md)` 의 STEP 1-4 결과물:
```
[DEFAULT]
user=ocid1.user.oc1..aaaaaaa...
fingerprint=xx:xx:...
tenancy=ocid1.tenancy.oc1..aaaaaaa...
region=ap-seoul-1
key_file=...
```

전체가 L2 결합. 처리 규칙:
- 메모리/임시파일에 보관 후 사용 즉시 폐기 (zero on free)
- `./setup.sh` 의 stdin 으로 직접 전달 (디스크 경유 최소화)
- 디스크에 임시 파일 저장 시 `mktemp` + `chmod 600` + 작업 후 `shred -u` (가능 시)
- 채팅에 "preview captured (5 lines)" 같은 카운트만 노출 가능

---

## 4. 안전한 전달 패턴

### 4-1. 미리보기 → setup.sh stdin (권장)

[local-execution.md](local-execution.md) 의 패턴 B (pty) 사용:
```python
child.expect(r"빈 줄에서 Ctrl\+D")
child.send(preview_text + "\n")
child.send("\x04")  # EOF
del preview_text  # 파이썬 GC 힌트
```

- preview_text 는 함수 로컬 변수로만 보관, 글로벌 X
- LLM 컨텍스트로 보낼 때는 마스킹된 사본만

### 4-2. .pem 경로 → setup.sh

```python
# .pem 자체가 아닌 "경로" 만 LLM 에게 알림
agent.notify("PEM detected at: ~/Downloads/oracle.pem")  # ✅ 경로만
agent.notify("PEM content: -----BEGIN ...")              # ❌ 절대 X
```

### 4-3. 클립보드 사용 시 정리

브라우저에서 `navigator.clipboard.readText()` 로 미리보기를 읽었다면, 사용 후 클립보드를 빈 문자열로 덮어쓰기:

```javascript
const preview = await navigator.clipboard.readText();
// ... 사용 ...
await navigator.clipboard.writeText("");  // 정리
```

### 4-4. 임시 파일 정리

```bash
TMP=$(mktemp)
chmod 600 "$TMP"
trap 'shred -u "$TMP" 2>/dev/null || rm -f "$TMP"' EXIT
# ... 사용 ...
```

---

## 5. 로그 / 스크린샷 / 트레이스

### 5-1. 자동 마스킹 정규식 (참고)

LLM 출력 또는 콘솔 캡처를 외부로 전송 전 다음 패턴을 redact 권장:

| 패턴 | 정규식 |
|---|---|
| Private Key 블록 | `-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----` |
| OCID (마지막 8자만 보존) | `(ocid1\.[a-z]+\.oc1\.[a-z0-9-]*\.)([a-z0-9]{20,})` → `$1***$REPLACED***` |
| Fingerprint | `(?:[a-f0-9]{2}:){15}[a-f0-9]{2}` |
| Discord Webhook | `https://(?:discord\.com\|discordapp\.com)/api/webhooks/\d+/[A-Za-z0-9_-]+` |

### 5-2. 스크린샷

OCI Console 화면 캡처 시 이메일/사용자명/OCID 가 들어갈 수 있음. 스크린샷을 LLM 컨텍스트로 전송 전:
- 사용자 동의
- 가능하면 dom snapshot (text only) 으로 대체 — 시각 정보 불필요한 경우

### 5-3. setup.sh / setup_init.sh 로그

`setup_init.log`, `launch_instance.log`, `setup_and_info.log` 에는 OCID 가 평문으로 들어감. 이 파일들을 외부 공유 시 마스킹 필수.

`.gitignore` 가 `*.log` 차단하지만, 사용자가 의도적으로 공유 시 주의 안내.

---

## 6. 사용자 동의 매트릭스

| 동작 | 동의 시점 | 동의 형태 |
|---|---|---|
| OCI Console 접근 시작 | 첫 브라우저 컨트롤 시 | "OCI Console 작업을 자동으로 진행할까요?" |
| `.pem` 파일 이동 | 다운로드 직후 | "방금 받은 파일을 레포 폴더로 옮겨도 될까요?" |
| `oci_config` 작성 | 미리보기 추출 직후 | "이 미리보기로 oci_config 를 만들어도 될까요?" (마스킹된 요약 표시) |
| `./setup_init.sh` 백그라운드 시작 | setup.sh 종료 직후 | "이제 인스턴스 자동 생성을 백그라운드에서 시작합니다. 시간/비용/계정 영향을 안내했나요?" |
| VCN 자동 생성 | setup.sh 의 [3/4] 단계 | "Free Tier 한도 내에서 VCN/Subnet 을 새로 만듭니다. 진행할까요?" |
| 인스턴스 생성 후 SSH 접속 | INSTANCE_CREATED 감지 직후 | "공용 IP 가 확인됐습니다. SSH 로 연결해볼까요?" |
| Discord webhook 등록 | 사용자가 URL 직접 제시했을 때 | URL 출처 확인 후 등록 |

---

## 7. 데이터 보존 / 폐기

| 데이터 | 보존 기간 | 폐기 방법 |
|---|---|---|
| 미리보기 텍스트 (메모리) | 함수 호출 단위 | 변수 스코프 종료 |
| 미리보기 텍스트 (임시 파일) | setup.sh 실행 시점만 | setup.sh 가 mktemp 후 mv 로 이동, trap 으로 정리 |
| `.pem` 파일 (Downloads) | 이동 후 즉시 | `rm "$ORIGINAL_PATH"` 또는 사용자 동의 후 보관 |
| `.pem` 파일 (레포) | 사용 기간 전체 | 인스턴스 생성 완료 후에도 추후 재실행 위해 보관. 사용자가 폐기 결정 |
| LLM 대화 기록 | 사용자 정책 | 마스킹된 사본만 보존, 원본 폐기 |

---

## 8. 외부 서비스 통합

| 서비스 | 정책 |
|---|---|
| GitHub | `.gitignore` 가 secrets 차단. PR 본문 / 이슈 / 코멘트에 L1/L2 절대 X |
| OCI | API 호출은 사용자 자격증명 사용. 호출 결과 (OCID 등) 은 L2, 마스킹 후 노출 |
| Discord | Webhook URL 은 L2. 알림 본문에 L1 X, 인스턴스 ID/IP 는 사용자 채널 한정 |
| Telegram (legacy) | 동일 정책 |
| 외부 LLM API | 미리보기/OCID 는 마스킹 후 전달. 가능하면 로컬 LLM 우선 |

---

## 9. 사고 대응 (Incident Response)

L1 노출 사고 발생 시:

1. **즉시 차단**: OCI Console 에서 해당 API 키 폐기 (Profile → API Keys → Delete). SSH 키면 인스턴스의 `~/.ssh/authorized_keys` 에서 해당 공개키 제거
2. **영향 평가**: 노출 위치(채팅/로그/PR), 노출 기간, 잠재 열람자 추정
3. **사용자 통보**: 명확한 사실관계 (어떤 데이터가 어디에 노출됐는지)
4. **재발 방지**: 마스킹 누락 지점 식별, 정책 업데이트

L2 노출은 사용자에게 알리고 자체 판단으로 키 재발급 여부 결정.
