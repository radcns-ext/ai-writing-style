#!/usr/bin/env bash
# 개발 repo(source)의 커밋을 하나씩 따라가며 납품용 repo(target)로 옮기는 헬퍼.
# 복사·커밋은 여기서 고정하고, 메시지를 다시 쓰는 건 deliver 스킬이 맡는다.
#
#   deliver.sh commits <target> [--from <rev>] [--ref <rev>] <dir>[:<dest>] ...
#   deliver.sh sync    <target> [--ref <rev>] [--force] [--quiet] <dir>[:<dest>] ...
#   deliver.sh commit  <target> <source-sha> <message-file>
#   deliver.sh record  <target> <source-sha>
#
# source 는 현재 디렉토리가 속한 git repo 다.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

state_file() { echo "$(git -C "$1" rev-parse --absolute-git-dir)/deliver-state"; }

last_delivered() {
  local sf
  sf="$(state_file "$1")"
  [ -f "$sf" ] && sed -n 's/^source_sha=//p' "$sf" || true
}

# 공통 인자 해석. 결과는 전역 SRC TARGET REF FROM FORCE QUIET MAPS SRC_DIRS DEST_DIRS 에 담는다.
parse_args() {
  REF="HEAD"; FROM=""; FORCE=0; QUIET=0; MAPS=(); SRC_DIRS=(); DEST_DIRS=()
  [ $# -ge 1 ] || die "target 경로가 필요하다"
  TARGET="$1"; shift
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref) REF="$2"; shift 2 ;;
      --from) FROM="$2"; shift 2 ;;
      --force) FORCE=1; shift ;;
      --quiet) QUIET=1; shift ;;
      *) MAPS+=("$1"); shift ;;
    esac
  done
  [ ${#MAPS[@]} -gt 0 ] || die "옮길 디렉토리를 하나 이상 지정해야 한다"

  SRC="$(git rev-parse --show-toplevel 2>/dev/null)" || die "현재 위치가 git repo 가 아니다"
  check_target

  local m dir dest
  for m in "${MAPS[@]}"; do
    dir="${m%%:*}"; dest="${m#*:}"
    [ "$m" = "$dir" ] && dest="$dir"
    dir="${dir%/}"; dest="${dest%/}"
    [ -n "$dir" ] && [ "$dir" != "." ] || die "source 디렉토리로 repo 루트 전체는 받지 않는다: $m"
    [ -n "$dest" ] && [ "$dest" != "." ] || die "target 루트에 바로 풀면 --delete 가 다른 납품분을 지운다: $m"
    SRC_DIRS+=("$dir"); DEST_DIRS+=("$dest")
  done
}

check_target() {
  [ -d "$TARGET" ] || die "target 이 없다: $TARGET"
  TARGET="$(cd "$TARGET" && pwd -P)"
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || die "target 이 git repo 가 아니다: $TARGET"
  [ "$(git -C "$TARGET" rev-parse --show-toplevel)" = "$TARGET" ] || die "target 은 repo 최상위여야 한다"
  if [ -n "${SRC:-}" ]; then
    [ "$(cd "$SRC" && pwd -P)" != "$TARGET" ] || die "source 와 target 이 같다"
  fi
}

cmd_commits() {
  parse_args "$@"
  local sha base
  sha="$(git -C "$SRC" rev-parse --verify "$REF^{commit}")" || die "ref 를 찾을 수 없다: $REF"
  base="${FROM:-$(last_delivered "$TARGET")}"

  local range="$sha"
  if [ -n "$base" ]; then
    git -C "$SRC" cat-file -e "$base^{commit}" 2>/dev/null || die "기준점 $base 를 source 에서 찾을 수 없다. rebase 됐으면 --from 으로 다시 지정한다"
    git -C "$SRC" merge-base --is-ancestor "$base" "$sha" || die "기준점 $base 가 $REF 의 조상이 아니다"
    range="$base..$sha"
    echo "기준점: $(git -C "$SRC" log -1 --format='%h %ad %s' --date=short "$base")"
  else
    echo "기준점: 없음 (첫 납품. 처음부터 전부 나온다)"
  fi
  echo "대상:   $(git -C "$SRC" log -1 --format='%h %ad %s' --date=short "$sha")"
  echo

  # 메인라인(first-parent)만 따라간다. 곁가지 커밋을 시간순으로 섞어 재생하면
  # 브랜치를 오가며 같은 파일이 앞뒤로 바뀌는 이력이 생긴다. 머지는 기능 하나로 본다.
  # path 필터는 rev-list 에 맡기지 않고 첫 부모와 직접 비교한다. --first-parent 와 같이 쓰면
  # 머지가 빠지는 경우가 있어서다.
  local c n=0 kind
  while read -r c; do
    if git -C "$SRC" rev-parse -q --verify "$c^1" >/dev/null; then
      git -C "$SRC" diff --quiet "$c^1" "$c" -- "${SRC_DIRS[@]}" && continue
    elif [ -z "$(git -C "$SRC" ls-tree --name-only "$c" -- "${SRC_DIRS[@]}")" ]; then
      continue
    fi
    kind="-"
    git -C "$SRC" rev-parse -q --verify "$c^2" >/dev/null && kind="M"
    git -C "$SRC" log -1 --format="%H %ad $kind %s" --date=short "$c"
    n=$((n + 1))
  done < <(git -C "$SRC" rev-list --first-parent --reverse "$range")
  echo
  echo "총 ${n}개 (M = 머지. 머지된 곁가지 커밋은 git log <sha>^1..<sha>^2 로 본다)"
}

cmd_sync() {
  parse_args "$@"

  # 납품 중에 섞이면 어떤 변경이 이번 커밋분인지 구분이 안 된다.
  if [ $FORCE -eq 0 ] && [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
    die "target 에 커밋 안 된 변경이 있다. 정리하거나 --force 로 실행한다"
  fi

  local sha
  sha="$(git -C "$SRC" rev-parse --verify "$REF^{commit}")" || die "ref 를 찾을 수 없다: $REF"

  local i
  for i in "${!SRC_DIRS[@]}"; do
    git -C "$SRC" cat-file -e "$sha:${SRC_DIRS[$i]}" 2>/dev/null || die "$REF 에 ${SRC_DIRS[$i]} 가 없다"
  done

  # trap 은 함수가 끝난 뒤에 돌아서 local 로 두면 이미 사라진 변수를 참조한다.
  DELIVER_TMP="$(mktemp -d)"
  trap 'rm -rf "$DELIVER_TMP"' EXIT

  # 작업 트리가 아니라 커밋된 스냅샷을 옮긴다. 기록하는 SHA 와 납품물이 정확히 일치해야 해서다.
  # git archive 라서 .gitattributes 의 export-ignore 도 그대로 먹는다.
  git -C "$SRC" archive --format=tar "$sha" -- "${SRC_DIRS[@]}" | tar -x -C "$DELIVER_TMP"

  local -a excl=(--exclude=.git --exclude=.deliverignore
    --exclude='.env' --exclude='.env.*' --exclude='.DS_Store'
    --exclude='.idea/' --exclude='.vscode/' --exclude='.claude/' --exclude='CLAUDE.md')
  [ -f "$SRC/.deliverignore" ] && excl+=("--exclude-from=$SRC/.deliverignore")
  [ -f "$TARGET/.deliverignore" ] && excl+=("--exclude-from=$TARGET/.deliverignore")

  for i in "${!SRC_DIRS[@]}"; do
    mkdir -p "$TARGET/${DEST_DIRS[$i]}"
    rsync -a --delete "${excl[@]}" "$DELIVER_TMP/${SRC_DIRS[$i]}/" "$TARGET/${DEST_DIRS[$i]}/"
  done

  if [ $QUIET -eq 0 ]; then
    echo "== source: $SRC"
    echo "ref: $REF ($sha)"
    if [ -n "$(git -C "$SRC" status --porcelain -- "${SRC_DIRS[@]}")" ]; then
      echo "note: source 에 커밋 안 된 변경이 있다. 납품에는 포함되지 않았다."
    fi
    echo
    echo "== target: $TARGET"
  fi
  git -C "$TARGET" status --short
}

cmd_commit() {
  [ $# -eq 3 ] || die "usage: deliver.sh commit <target> <source-sha> <message-file>"
  TARGET="$1"
  local sha="$2" msg="$3"
  SRC="$(git rev-parse --show-toplevel 2>/dev/null)" || die "현재 위치가 git repo 가 아니다"
  check_target
  [ -s "$msg" ] || die "메시지 파일이 비어 있다: $msg"
  sha="$(git -C "$SRC" rev-parse --verify "$sha^{commit}")" || die "source 커밋을 찾을 수 없다: $2"

  git -C "$TARGET" add -A
  if git -C "$TARGET" diff --cached --quiet; then
    # 제외 목록에 걸린 파일만 바뀐 커밋이면 옮길 게 없다. 기준점만 앞으로 민다.
    echo "skip: 옮길 변경이 없다 ($(git -C "$SRC" log -1 --format='%h %s' "$sha"))"
  else
    # 작성 시각은 source 커밋을 따른다. 납품 시각으로 몰리면 이력이 하루에 전부 쌓인다.
    GIT_AUTHOR_DATE="$(git -C "$SRC" log -1 --format=%aI "$sha")" \
      git -C "$TARGET" commit -q --cleanup=strip -F "$msg"
    git -C "$TARGET" log -1 --format='commit: %h %ad %s' --date=short
  fi
  cmd_record "$TARGET" "$sha" >/dev/null
}

cmd_record() {
  [ $# -eq 2 ] || die "usage: deliver.sh record <target> <source-sha>"
  local sf
  sf="$(state_file "$1")"
  printf 'source_sha=%s\ndelivered_at=%s\n' "$2" "$(date '+%Y-%m-%dT%H:%M:%S%z')" > "$sf"
  echo "기준점 기록: $2 -> $sf"
}

case "${1:-}" in
  commits) shift; cmd_commits "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  commit) shift; cmd_commit "$@" ;;
  record) shift; cmd_record "$@" ;;
  *) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
