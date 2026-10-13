#!/usr/bin/env bash
# 개발 repo(source)의 커밋을 하나씩 따라가며 납품용 repo(target)로 옮기는 헬퍼.
# 복사·커밋은 여기서 고정하고, 메시지를 다시 쓰는 건 deliver 스킬이 맡는다.
#
#   deliver.sh resolve <source-path> <target-path> [<source-path> <target-path> ...]
#   deliver.sh commits --src <repo> <target> [--from <rev>] [--ref <rev>] <dir>[:<dest>] ...
#   deliver.sh sync    --src <repo> <target> [--ref <rev>] [--force] [--quiet] <dir>[:<dest>] ...
#   deliver.sh commit  --src <repo> <target> <source-sha> <message-file> <dir>[:<dest>] ...
#   deliver.sh record  --src <repo> <target> <source-sha> <dir>[:<dest>] ...
#
# <dir> 는 source repo 기준, <dest> 는 target repo 기준 경로다. repo 전체는 "." 로 쓴다.
# --src 를 안 주면 현재 디렉토리가 속한 repo 를 source 로 본다.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }

# 경로가 속한 repo 최상위와 그 안에서의 상대 경로를 찾는다. 아직 없는 경로면
# 존재하는 상위 디렉토리까지 올라가서 찾고 나머지를 이어 붙인다.
locate() {
  local p="$1" rest="" prefix root
  while [ ! -d "$p" ]; do
    rest="$(basename "$p")${rest:+/$rest}"
    p="$(dirname "$p")"
  done
  root="$(git -C "$p" rev-parse --show-toplevel 2>/dev/null)" || die "git repo 안에 있는 경로가 아니다: $1"
  prefix="$(git -C "$p" rev-parse --show-prefix)"
  prefix="${prefix%/}${rest:+${prefix:+/}$rest}"
  LOC_ROOT="$root"; LOC_REL="${prefix:-.}"
}

# 경로 쌍을 받아 (source repo, target repo) 조합별로 묶어서 보여준다.
# 같은 조합의 매핑은 한 번에 옮겨야 source 커밋 하나가 target 커밋 하나로 남는다.
cmd_resolve() {
  [ $# -ge 2 ] && [ $(($# % 2)) -eq 0 ] || die "usage: deliver.sh resolve <source-path> <target-path> [<source-path> <target-path> ...]"
  local -a keys=() maps=()
  local sroot srel troot trel key i found
  while [ $# -gt 0 ]; do
    [ -d "$1" ] || die "source 경로가 없다: $1"
    locate "$1"; sroot="$LOC_ROOT"; srel="$LOC_REL"
    locate "$2"; troot="$LOC_ROOT"; trel="$LOC_REL"
    [ "$sroot" != "$troot" ] || die "source 와 target 이 같은 repo 다: $1 -> $2"
    key="$sroot|$troot"; found=""
    for i in "${!keys[@]}"; do
      [ "${keys[$i]}" = "$key" ] && found="$i"
    done
    if [ -z "$found" ]; then
      keys+=("$key"); maps+=("$srel:$trel")
    else
      maps[$found]="${maps[$found]}"$'\n'"$srel:$trel"
    fi
    shift 2
  done
  for i in "${!keys[@]}"; do
    echo "GROUP $((i + 1))"
    echo "SRC=${keys[$i]%%|*}"
    echo "TARGET=${keys[$i]#*|}"
    printf '%s\n' "${maps[$i]}" | sed 's/^/MAP=/'
    echo
  done
}

# 공통 인자 해석. 옵션을 뺀 나머지는 POS 에 순서대로 담는다.
parse_opts() {
  SRC=""; REF="HEAD"; FROM=""; FORCE=0; QUIET=0; POS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --src) SRC="$2"; shift 2 ;;
      --ref) REF="$2"; shift 2 ;;
      --from) FROM="$2"; shift 2 ;;
      --force) FORCE=1; shift ;;
      --quiet) QUIET=1; shift ;;
      *) POS+=("$1"); shift ;;
    esac
  done
  if [ -n "$SRC" ]; then
    SRC="$(git -C "$SRC" rev-parse --show-toplevel 2>/dev/null)" || die "--src 가 git repo 가 아니다"
  else
    SRC="$(git rev-parse --show-toplevel 2>/dev/null)" || die "--src 를 주거나 source repo 안에서 실행한다"
  fi
}

check_target() {
  [ -d "$TARGET" ] || die "target 이 없다: $TARGET"
  TARGET="$(cd "$TARGET" && pwd -P)"
  git -C "$TARGET" rev-parse --git-dir >/dev/null 2>&1 || die "target 이 git repo 가 아니다: $TARGET"
  [ "$(git -C "$TARGET" rev-parse --show-toplevel)" = "$TARGET" ] || die "target 은 repo 최상위여야 한다. 하위 경로는 <dest> 로 준다"
  [ "$(cd "$SRC" && pwd -P)" != "$TARGET" ] || die "source 와 target 이 같다"
}

parse_maps() {
  MAPS=(); SRC_DIRS=(); DEST_DIRS=()
  [ $# -gt 0 ] || die "옮길 디렉토리를 하나 이상 지정해야 한다"
  local m dir dest
  for m in "$@"; do
    dir="${m%%:*}"; dest="${m#*:}"
    [ "$m" = "$dir" ] && dest="$dir"
    dir="${dir%/}"; dest="${dest%/}"
    [ -n "$dir" ] || dir="."
    [ -n "$dest" ] || dest="."
    MAPS+=("$dir:$dest"); SRC_DIRS+=("$dir"); DEST_DIRS+=("$dest")
  done
  # target 루트에 풀면 rsync --delete 가 그 repo 의 다른 파일을 전부 지운다.
  # 매핑이 하나뿐일 때만, 즉 target repo 를 통째로 이 source 에 맞출 때만 허용한다.
  if [ ${#MAPS[@]} -gt 1 ]; then
    for dest in "${DEST_DIRS[@]}"; do
      [ "$dest" != "." ] || die "여러 디렉토리를 옮길 때는 target 루트(.)를 쓸 수 없다"
    done
  fi
}

# 기준점은 source repo + 매핑 조합마다 따로 둔다. 한 target 에 여러 source 를 넣거나
# 같은 source 의 다른 디렉토리를 따로 넣을 때 서로 덮어쓰지 않게 하려는 것이다.
state_file() {
  local key
  key="$(printf '%s\n' "$SRC" "${MAPS[@]}" | shasum | cut -c1-12)"
  echo "$(git -C "$TARGET" rev-parse --absolute-git-dir)/deliver/$key"
}

last_delivered() {
  local sf
  sf="$(state_file)"
  [ -f "$sf" ] && sed -n 's/^source_sha=//p' "$sf" || true
}

write_state() {
  local sf
  sf="$(state_file)"
  mkdir -p "$(dirname "$sf")"
  {
    echo "source_repo=$SRC"
    echo "maps=${MAPS[*]}"
    echo "source_sha=$1"
    echo "delivered_at=$(date '+%Y-%m-%dT%H:%M:%S%z')"
  } > "$sf"
  echo "기준점 기록: $1 -> $sf"
}

cmd_commits() {
  parse_opts "$@"
  [ ${#POS[@]} -ge 2 ] || die "usage: deliver.sh commits --src <repo> <target> <maps>"
  TARGET="${POS[0]}"; check_target
  parse_maps "${POS[@]:1}"

  local sha base
  sha="$(git -C "$SRC" rev-parse --verify "$REF^{commit}")" || die "ref 를 찾을 수 없다: $REF"
  base="${FROM:-$(last_delivered)}"

  local range="$sha"
  echo "source: $SRC"
  echo "target: $TARGET"
  echo "maps:   ${MAPS[*]}"
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
  echo "총 ${n}개 (M = 머지. 머지된 곁가지 커밋은 git -C <source> log <sha>^1..<sha>^2 로 본다)"
}

cmd_sync() {
  parse_opts "$@"
  [ ${#POS[@]} -ge 2 ] || die "usage: deliver.sh sync --src <repo> <target> <maps>"
  TARGET="${POS[0]}"; check_target
  parse_maps "${POS[@]:1}"

  # 납품 중에 섞이면 어떤 변경이 이번 커밋분인지 구분이 안 된다.
  if [ $FORCE -eq 0 ] && [ -n "$(git -C "$TARGET" status --porcelain)" ]; then
    die "target 에 커밋 안 된 변경이 있다. 정리하거나 --force 로 실행한다"
  fi

  local sha i
  sha="$(git -C "$SRC" rev-parse --verify "$REF^{commit}")" || die "ref 를 찾을 수 없다: $REF"
  for i in "${!SRC_DIRS[@]}"; do
    [ "${SRC_DIRS[$i]}" = "." ] && continue
    git -C "$SRC" cat-file -e "$sha:${SRC_DIRS[$i]}" 2>/dev/null || die "$REF 에 ${SRC_DIRS[$i]} 가 없다"
  done

  # trap 은 함수가 끝난 뒤에 돌아서 local 로 두면 이미 사라진 변수를 참조한다.
  DELIVER_TMP="$(mktemp -d)"
  trap 'rm -rf "$DELIVER_TMP"' EXIT

  # 작업 트리가 아니라 커밋된 스냅샷을 옮긴다. 기록하는 SHA 와 납품물이 정확히 일치해야 해서다.
  # git archive 라서 .gitattributes 의 export-ignore 도 그대로 먹는다.
  git -C "$SRC" archive --format=tar "$sha" -- "${SRC_DIRS[@]}" | tar -x -C "$DELIVER_TMP"

  local -a excl=(--exclude=/.git --exclude=.deliverignore
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
  parse_opts "$@"
  [ ${#POS[@]} -ge 4 ] || die "usage: deliver.sh commit --src <repo> <target> <source-sha> <message-file> <maps>"
  TARGET="${POS[0]}"; check_target
  local sha="${POS[1]}" msg="${POS[2]}"
  parse_maps "${POS[@]:3}"
  [ -s "$msg" ] || die "메시지 파일이 비어 있다: $msg"
  sha="$(git -C "$SRC" rev-parse --verify "$sha^{commit}")" || die "source 커밋을 찾을 수 없다: ${POS[1]}"

  # 이번 매핑의 경로만 올린다. target 의 다른 디렉토리는 다른 source 몫일 수 있다.
  git -C "$TARGET" add -A -- "${DEST_DIRS[@]}"
  if git -C "$TARGET" diff --cached --quiet; then
    # 제외 목록에 걸린 파일만 바뀐 커밋이면 옮길 게 없다. 기준점만 앞으로 민다.
    echo "skip: 옮길 변경이 없다 ($(git -C "$SRC" log -1 --format='%h %s' "$sha"))"
  else
    # 작성 시각은 source 커밋을 따른다. 납품 시각으로 몰리면 이력이 하루에 전부 쌓인다.
    GIT_AUTHOR_DATE="$(git -C "$SRC" log -1 --format=%aI "$sha")" \
      git -C "$TARGET" commit -q --cleanup=strip -F "$msg"
    git -C "$TARGET" log -1 --format='commit: %h %ad %s' --date=short
  fi
  write_state "$sha" >/dev/null
}

cmd_record() {
  parse_opts "$@"
  [ ${#POS[@]} -ge 3 ] || die "usage: deliver.sh record --src <repo> <target> <source-sha> <maps>"
  TARGET="${POS[0]}"; check_target
  local sha="${POS[1]}"
  parse_maps "${POS[@]:2}"
  sha="$(git -C "$SRC" rev-parse --verify "$sha^{commit}")" || die "source 커밋을 찾을 수 없다: ${POS[1]}"
  write_state "$sha"
}

case "${1:-}" in
  resolve) shift; cmd_resolve "$@" ;;
  commits) shift; cmd_commits "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  commit) shift; cmd_commit "$@" ;;
  record) shift; cmd_record "$@" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
