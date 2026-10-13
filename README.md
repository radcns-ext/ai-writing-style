# writing-style — 커밋 메시지·주석 문체 스킬

Claude Code 가 커밋 메시지와 코드 주석을 **사람이 쓴 것처럼** 남기게 해주는 스킬이다. 납품용 repo 로 코드를 옮기면서 커밋까지 정리해주는 `deliver` 스킬도 같이 들어 있다.
톤은 옆자리 동료한테 설명하듯, 보고서처럼 딱딱하지 않게 잡는다.
"무엇을 바꿨나" 는 diff 와 코드가 이미 말한다. 이 스킬은 **"왜"** 가 남게 한다.

## 설치

```
/plugin marketplace add http://gitlab.radcns.com/ai-set/writing-style.git
/plugin install writing-style@radcns-dev
```

모든 프로젝트에서 자동으로 잡힌다. 업데이트는 `/plugin update writing-style`.
플러그인 없이 쓰려면 `skills/writing-style/` 폴더를 `~/.claude/skills/` 또는 프로젝트 `.claude/skills/` 에 복사한다.

## 언제 발동하나

| 상황 | 예 |
|---|---|
| 커밋 메시지를 쓸 때 | "커밋해줘", "커밋 메시지 써줘", "이거 커밋 나눠서" |
| 주석을 달거나 정리할 때 | "주석 달아줘", "주석 정리해줘", "comment" |
| 방어 코드·엣지 케이스·비직관 로직을 쓸 때 | 별도 요청 없이 코드 작성 중 자동 적용 |
| 납품용 repo 로 옮길 때 (직접 호출만) | `/writing-style:deliver api web -> ~/work/client` |

---

## 1. 커밋 메시지 — AS-IS → TO-BE

### 예 1. 태그 + 엠대시 + 불릿 나열

**AS-IS**
```
[Feat] 관리자 대리 주문 등록 기능 — DB/메뉴/Lambda

관리자가 특정 파트너사 명의로 주문을 대신 등록할 수 있는 기반을 마련.
- orders.proxy_admin_id 컬럼 추가 (V121)
- SUPER_ADMIN 전용 대리 주문 메뉴 신설
- Lambda 3종에 대리 모드 분기 추가
```
문제: 태그, 엠대시 부연, 개조식 종결("마련."), 기계적 불릿, 확인 안 된 번호(실제는 V123)가 한 번에 들어 있다. 무엇을 했는지만 있고 왜 했는지가 없다.

**TO-BE**
```
관리자가 파트너사 명의로 주문 대리 등록

메뉴는 SUPER_ADMIN 전용으로 따로 뺐다. 파트너 쪽 화면에는 대리 등록이라는
표시가 뜨고, 취소나 재주문은 할 수 없게 막아뒀다. 알림 메일은 일부러 보내지 않는다.
```

### 예 2. "~수정" 만 있고 원인이 없는 제목

**AS-IS**
```
[Fix] 주문 기간검색 날짜 오류 수정
```

**TO-BE**
```
주문 기간검색에서 마지막 날짜가 빠지던 문제

toISOString 을 쓰다 보니 UTC 로 밀려서 31일 주문이 검색에 안 걸리고 있었다.
KST 오프셋을 고정해서 해결했다.
```

### 예 3. 본문이 필요 없는 커밋에 본문을 붙임

**AS-IS**
```
[Chore] 카탈로그 삭제 주문 표시 — 목록 노출 정책 반영

카탈로그가 삭제된 주문도 목록에 표시되도록 수정.
- OrderRepository 조건 변경
- 테스트 통과 148/148
```

**TO-BE**
```
카탈로그 삭제된 주문도 목록에 표시
```
제목만으로 충분하면 제목만 쓴다. 테스트 수치는 커밋에 남길 이유가 없다.

### 예 4. 엠대시로 제목을 늘림

**AS-IS**
```
주문추출 개선 — 오더별 행 분리 / 카탈로그 컬럼 추가
```

**TO-BE**
```
주문 추출을 오더별 한 행으로

한 주문이 여러 행으로 흩어져 있어서 엑셀로 합계 내기가 번거로웠다. 하는 김에
카탈로그 컬럼도 같이 붙였다.
```

### 예 5. 머지 충돌을 푼 커밋 — 결정의 이유를 남김

**AS-IS**
```
Merge branch 'feature/xxx' into develop
```

**TO-BE**
```
Merge branch 'feature/xxx' into develop

충돌 네 곳은 양쪽이 각자 추가한 거라 전부 살렸다. 에러 코드 CAT015 는 이미
주문 참조 삭제 경고가 쓰고 있고 FE 가 문자열로 판정하고 있어서, 이미지·표지 코드는
CAT021~026 으로 옮겼다.
```

### 예 6. 이모지·gitmoji

**AS-IS**
```
✨ 시즌 진행중 여러 개 동시 허용 🚀

- ✅ API 검증 로직 변경
- ✅ 화면 배지 수정
```

**TO-BE**
```
시즌 진행중(ACTIVE) 여러 개 동시 허용

운영 쪽에서 시즌을 겹쳐서 돌리고 싶다는 요청이 있어서 하나만 허용하던 제약을 풀었다.
```
이모지, gitmoji, 체크 표시 같은 장식은 하나만 있어도 바로 티가 난다. 강조가 필요하면 말로 쓴다.

### 예 7. AI 푸터

**AS-IS**
```
시즌 콤보 폭 확장

Co-Authored-By: Claude <noreply@anthropic.com>
```

**TO-BE**
```
시즌 콤보 폭 확장
```

### 커밋을 나눌 때

기능 단위로 자른다. 영역(백엔드/프론트)이 아니라 "무엇이 달라졌는가" 로 묶고, 나눈 목록을 먼저 보여준 뒤 승인받고 커밋한다.

**AS-IS** (영역별)
```
1. [BE] 시즌 API 변경
2. [FE] 시즌 화면 변경
3. [DB] 인덱스 제거
```

**TO-BE** (기능별)
```
1. 머지 65bf51c 에서 빠진 manager-api 주문 코드 복원      ← 별개 사안
2. 시즌 진행중(ACTIVE) 여러 개 동시 허용                 ← DB+API+화면 한 커밋
```

### 커밋 직전 자가 점검

- 제목에 `—` 가 있는가
- 아이콘·이모지·장식 기호가 섞여 있는가
- 모든 제목이 비슷한 길이인가
- 모든 본문이 불릿인가
- 종결어미가 전부 같은가
- 확인하지 않은 번호·이름이 들어갔는가

---

## 2. 주석 — AS-IS → TO-BE

### 예 1. 코드 재진술

**AS-IS**
```java
// 로그인 실패 횟수를 0으로 초기화한다
admin.resetLoginFailCount();
```
코드가 이미 말하고 있다. 지운다.

**TO-BE**
```java
admin.resetLoginFailCount();
```

### 예 2. 숫자에 근거가 없음

**AS-IS**
```java
// 관리자 토큰 만료 시간
private int adminRefreshTokenExpirationMinutes = 30;
```

**TO-BE**
```java
// 관리자 refresh 는 유휴 30분 sliding 으로 둔다. 직원 계정과 정책을 분리했다(2026-08-29).
private int adminRefreshTokenExpirationMinutes = 30;
```

### 예 3. 함정을 이모지와 느낌표로

**AS-IS**
```swift
// ⚠️⚠️ 절대 여기서 super.openURL 호출하지 말 것!!! 크래시남!!!
```

**TO-BE**
```swift
// 주의: 여기서 super openURL 을 부르면 isa-swizzle 때문에 무력화돼서 크래시가 난다(2026-09-02 확인).
```

### 예 4. 계산된 숫자

**AS-IS**
```css
.badge { max-width: 98px; }
```
98 이 어디서 왔는지 아무도 모른다. 썸네일 폭을 바꾸면 조용히 깨진다.

**TO-BE**
```css
/* 98px = 썸네일 110px − 좌우 margin 6px×2. 썸네일 폭이 바뀌면 여기도 같이 바꿔야 한다. */
.badge { max-width: 98px; }
```

### 예 5. 비직관적 방어 코드

**AS-IS**
```js
if (selected.value.hasOrderPermission !== false) return true
```

**TO-BE**
```js
// === true 로 확인한다. !== false 로 두면 필드가 빠졌을 때 권한이 있는 걸로 열려버린다.
if (selected.value.hasOrderPermission === true) return true
```

### 예 6. 죽은 주석과 근거 없는 TODO

**AS-IS**
```java
// TODO: 나중에 리팩토링
// int oldLimit = 50;
// return repo.findTop50(...);
List<Season> list = repo.findActive(pageable);
```

**TO-BE**
```java
List<Season> list = repo.findActive(pageable);
```
주석 처리된 옛 코드는 git 에 있다. TODO 는 무엇을 왜 언제까지인지 없으면 쓰지 않는다.

### 예 7. 확인 안 된 것을 단정

**AS-IS**
```python
# S3 는 HEAD 요청을 지원하지 않는다
```

**TO-BE**
```python
# presigned URL 은 서명한 메서드(GET)로만 통해서 HEAD 는 403 이 난다(2026-09-04 실측). 추정: 서명 대상에 메서드가 들어가기 때문.
```

### 주석 규칙 요약

1. 아이콘·이모지·장식 기호 금지. 경고는 `주의:`
2. "무엇" 이 아니라 "왜"
3. 함정은 `주의:` 한 줄
4. 결정에는 근거 한 조각 (날짜·이슈·changelog)
5. 한 줄로 되면 트레일링
6. 한국어 평서체. 명령조보다 이유가 보이게. 확인 안 된 건 "추정"

---

## 3. 납품 repo 로 옮기기 — `/writing-style:deliver`

개발 repo 의 커밋을 **하나씩 따라가며** 납품용 repo 로 옮긴다. source 커밋 하나가 target 커밋 하나가 되고, 메시지는 원래 메시지를 바탕으로 위 커밋 규칙에 맞게 다시 쓴다. 자동으로 발동하지 않고 직접 불렀을 때만 돈다.

```
# 개발 repo 안에서
/writing-style:deliver api web/admin -> ~/work/client-delivery
/writing-style:deliver services/api:server -> ~/work/client-delivery     # 경로를 바꿔서
/writing-style:deliver api -> ~/work/client-delivery --from v1.3.0       # 이 시점 다음부터
```

흐름은 이렇다.

1. 지난 납품 이후 고른 디렉토리를 건드린 source 커밋 목록을 뽑는다. 메인라인만 따라가고, 머지는 곁가지 전체를 커밋 하나로 본다.
2. 커밋마다 원래 메시지와 diff 를 읽고 target 메시지를 쓴다. 사내 티켓 번호, 커밋 해시, 브랜치 이름 같은 내부 정보는 지우고, "wip", "오타" 같은 커밋은 다음 커밋과 합치자고 제안한다.
3. **source → target 메시지 대응표를 먼저 보여준다.** 승인해야 다음으로 넘어간다.
4. 오래된 것부터 하나씩 그 시점 스냅샷을 rsync 하고 커밋한다. 작성 시각은 source 커밋 시각을 따른다. push 는 하지 않는다.
5. 커밋할 때마다 source SHA 를 target 의 `.git/deliver-state` 에 남긴다. 납품물에는 안 들어가고, 중간에 멈춰도 다음에 이어서 할 수 있다.

예를 들면 이렇게 옮겨진다.

```
source (개발)                              target (납품)
a1b2c3d fix: 날짜 버그 (#231)        →     주문 기간검색에서 마지막 날짜가 빠지던 문제
d4e5f6a wip                          ┐
0718293 feat: 시즌 동시진행 JIRA-88  ┘ →   시즌 진행중 여러 개 동시 허용
8a9b0c1 Merge branch 'feat/export'   →     주문 추출을 오더별 한 행으로
```

첫 납품이라 기준점이 없으면 처음부터 다 옮길지, 특정 시점을 "초기 코드" 커밋 하나로 넣고 그 다음부터 옮길지 먼저 물어본다.

빼야 할 파일은 이렇게 걸러진다.

- 항상 빠지는 것: `.git`, `.env*`, `.idea/`, `.vscode/`, `.claude/`, `CLAUDE.md`, `.DS_Store`
- 그 밖에는 source 나 target 루트에 `.deliverignore` 를 두면 된다(rsync exclude 형식). `.gitattributes` 의 `export-ignore` 도 적용된다.

```
# .deliverignore
*.local.yml
docs/internal/
scripts/dev-*
```

target 에 커밋 안 된 변경이 있으면 이번 납품분과 섞이지 않게 멈춘다.

---

## 참고

- 커밋 실행 여부는 스킬이 정하지 않는다. 문체만 다룬다.
- AI 도구 푸터를 넣지 않는 것이 규칙이다. Claude Code `settings.json` 의 `attribution` 을 비워두면 일관된다:
  ```json
  { "attribution": { "commit": "", "pr": "", "sessionUrl": false } }
  ```
