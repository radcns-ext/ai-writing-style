---
name: deliver
description: 개발 repo 의 커밋을 하나씩 따라가며 납품용 repo 로 옮긴다. 각 커밋 메시지는 원래 메시지를 바탕으로 writing-style 규칙에 맞게 다시 쓰고, 승인받은 뒤 커밋한다. 사용자가 /deliver 로 직접 부를 때만 쓴다.
argument-hint: <dir>[:<dest>] ... -> <target 경로> [--from <rev>] [--ref <rev>]
disable-model-invocation: true
---

# deliver — 개발 repo 커밋을 납품 repo 로 옮기기

지금 있는 개발 repo(source)에서 고른 디렉토리의 변경을, **source 커밋 하나당 target 커밋 하나씩** 순서대로 옮긴다. 메시지는 source 커밋 메시지를 바탕으로 writing-style 규칙에 맞게 다시 쓴다. 파일 복사와 커밋은 스크립트가 하고, 이 스킬은 커밋 목록을 정리하고 메시지를 쓰는 쪽을 맡는다.

받은 인자: `$ARGUMENTS`

## 0. 인자 읽기

형식은 `<dir>[:<dest>] ... -> <target>` 이다.

- `api web/admin -> ~/work/client` : `api/`, `web/admin/` 을 target 의 같은 경로로
- `services/api:server -> ~/work/client` : source 의 `services/api/` 를 target 의 `server/` 로
- `--from <rev>` : 이 커밋 다음부터 옮긴다. 안 주면 지난 납품 기준점부터
- `--ref <rev>` : 이 커밋까지 옮긴다. 안 주면 HEAD

`->` 가 없거나 디렉토리나 target 이 비어 있으면, 추측하지 말고 사용자에게 물어본다.

스크립트는 이 스킬 디렉토리의 `scripts/deliver.sh` 이고, 항상 **source repo 안에서** 실행한다. 아래에서 `<maps>` 는 인자로 받은 `<dir>[:<dest>]` 목록이다.

## 1. 옮길 커밋 목록 뽑기

```
bash <skill-dir>/scripts/deliver.sh commits <target> [--from <rev>] [--ref <rev>] <maps>
```

- 고른 디렉토리를 실제로 건드린 커밋만 나온다. 다른 디렉토리만 바꾼 커밋은 알아서 빠진다.
- 메인라인(first-parent)만 따라간다. 머지 커밋은 `M` 표시가 붙는다. 머지는 곁가지 브랜치 전체를 커밋 하나로 옮기니까, 그 안의 커밋은 `git log <sha>^1..<sha>^2` 로 읽어서 메시지에 반영한다.
- 0개면 옮길 게 없다고 알려주고 끝낸다.

### 첫 납품이라 기준점이 없을 때

목록이 처음부터 전부 나온다. 이력이 길면 다 옮기는 게 맞는지 사용자에게 먼저 물어본다. 보통은 둘 중 하나다.

- **전부 재생:** 처음 커밋부터 하나씩 옮긴다.
- **시작점부터:** 사용자가 고른 커밋 `<base>` 시점을 "초기 코드" 커밋 하나로 넣고, 그 다음부터 하나씩 옮긴다. 순서는 `sync --ref <base>` → `commit <target> <base> <메시지>` 이고, 그러면 기준점이 `<base>` 로 기록되니까 1단계를 다시 돌리면 그 다음 커밋부터 나온다.

## 2. 커밋 정리와 메시지 쓰기

각 source 커밋의 메시지와 내용(`git show --stat <sha>`, 필요하면 diff)을 읽고 target 메시지를 쓴다.

**원래 메시지가 출발점이다.** 무슨 일이 있었는지는 원래 메시지에서 가져오고, 표현만 writing-style 규칙에 맞게 다듬는다(말하듯 쓰기, 아이콘·이모지 금지, 엠대시 금지, 태그 금지, AI 푸터 금지). 원래 메시지가 이미 괜찮으면 거의 그대로 써도 된다. 원래 메시지가 "수정", "wip" 처럼 정보가 없으면 diff 를 보고 실제로 바뀐 걸 쓴다. 확인 안 되는 이유를 지어내지 않는다.

납품이라서 더 신경 쓸 것:

- **내부 정보를 흘리지 않는다.** source 커밋 해시, 사내 티켓 번호(`JIRA-123`, `#45` 같은 것), 개발 repo 나 브랜치 이름, 사내 URL, 동료 이름은 지운다. 고객이 읽어도 되는 말로 바꾼다.
- **머지 커밋의 `Merge branch ...` 는 그대로 쓰지 않는다.** 곁가지 커밋들을 읽고 그 기능이 뭔지를 쓴다.
- **합칠지 제안한다.** "오타", "다시 되돌림", "wip" 처럼 혼자서는 의미 없는 커밋은 바로 다음 커밋과 합치자고 제안한다. 합치는 건 쉽다. 앞 커밋은 건너뛰고 뒤 커밋 시점으로 sync 하면 앞 변경이 같이 들어간다. 단, 사용자가 원하지 않으면 1:1 그대로 둔다.

## 3. 승인받기

커밋하기 전에 전체 계획을 표로 보여준다.

```
| # | source                          | target 메시지                          |
|---|---------------------------------|----------------------------------------|
| 1 | a1b2c3d 09-02 fix: 날짜 버그     | 주문 기간검색에서 마지막 날짜가 빠지던 문제 |
|   |                                 |   (본문) toISOString 을 쓰다 보니 ...     |
| 2 | d4e5f6a 09-03 wip               | 3번과 합침                              |
| 3 | 0718293 09-04 시즌 동시 진행     | 시즌 진행중 여러 개 동시 허용              |
| 4 | 8a9b0c1 09-08 Merge feat/export  | 주문 추출을 오더별 한 행으로               |
```

사용자가 고치라는 건 고치고 다시 보여준다. **승인을 받은 다음에만** 4단계로 넘어간다.

## 4. 하나씩 옮기고 커밋

승인한 목록을 **오래된 것부터** 하나씩 처리한다. 합치기로 한 커밋은 건너뛰고, 묶음의 마지막 커밋에서 처리한다.

```
bash <skill-dir>/scripts/deliver.sh sync <target> --quiet --ref <sha> <maps>
# 메시지를 임시 파일에 쓴다 (첫 줄 제목, 빈 줄, 본문)
bash <skill-dir>/scripts/deliver.sh commit <target> <sha> <메시지 파일>
```

- `sync` 는 그 커밋 시점의 스냅샷을 target 에 덮어쓴다. source 에서 지운 파일은 target 에서도 지워진다. `.git`, `.env*`, `.idea/`, `.vscode/`, `.claude/`, `CLAUDE.md`, `.DS_Store` 는 늘 빠지고, source 나 target 루트의 `.deliverignore`(rsync exclude 형식)와 `.gitattributes` 의 `export-ignore` 도 적용된다.
- `commit` 은 target 에서 전부 add 하고 커밋한 다음, 기준점을 그 source 커밋으로 옮긴다. 작성 시각은 source 커밋 시각을 따르고, 작성자는 target repo 의 git 설정을 쓴다. 제외 목록에 걸린 파일만 바뀐 커밋이면 `skip` 이 나오고 기준점만 넘어간다.
- 커밋할 때마다 기준점이 기록되니까, 중간에 멈춰도 다음에 1단계부터 다시 돌리면 이어서 할 수 있다.
- 처음 `sync` 는 target 에 커밋 안 된 변경이 있으면 멈춘다. 사용자가 괜찮다고 하기 전에는 `--force` 를 붙이지 않는다.
- 스크립트가 에러로 끝나면 거기서 멈추고 메시지를 그대로 전한다. 우회해서 직접 복사하거나 커밋하지 않는다.
- target `user.name` 이 비어 있으면 시작 전에 알려준다.
- `push` 는 하지 않는다. 사용자가 따로 말할 때만.

다 끝나면 `git -C <target> log --format='%h %ad %s' --date=short -n <개수>` 로 결과를 보여준다.
