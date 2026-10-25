#!/usr/bin/env bash
# Mac 에 여러 개 깔린 Godot 를 하나만 남기고 정리.
#  - 남길 것: Godot 4.7 중 하나 → /Applications/Godot.app 로 둔다 (이미 거기 있으면 그대로)
#  - 나머지: 휴지통(~/.Trash)으로 이동. 삭제가 아니라서 Finder 휴지통에서 되살릴 수 있음
#  - 지우기 전에 목록을 보여주고 y 를 입력해야 진행
#  - Godot 의 에디터 설정/프로젝트 목록(~/Library/Application Support/Godot)은 건드리지 않음
# 사용: curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/cleanup_godot.sh | bash
set -uo pipefail
GAME_DIR="${GAME_DIR:-$HOME/Game/zerosum}"
KEEP_TARGET="${KEEP_TARGET:-/Applications/Godot.app}"
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [ -n "$here" ] && [ -f "$here/godot_find.sh" ]; then
  . "$here/godot_find.sh"
else
  . <(curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/godot_find.sh)
fi

# 1) 후보 수집: Spotlight(번들 ID) + 흔한 위치
list="$(mktemp)"
if command -v mdfind >/dev/null 2>&1; then
  mdfind "kMDItemCFBundleIdentifier == 'org.godotengine.godot'" 2>/dev/null >> "$list"
fi
for d in /Applications "$HOME/Applications" "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents" "$GAME_DIR/_engine" "$HOME/Game/_engine" ${GODOT_SEARCH_DIRS:-}; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 3 \( -iname "Godot*.app" -o -iname "Godot_v*" \) -not -path "*/Contents/*" -not -iname "*.zip" 2>/dev/null >> "$list"
done
apps=()
while IFS= read -r p; do
  [ -n "$p" ] && [ -e "$p" ] || continue
  case "$p" in *.Trash/*) continue ;; esac
  dup=0; for a in "${apps[@]:-}"; do [ "$a" = "$p" ] && dup=1; done
  [ $dup = 0 ] && apps+=("$p")
done < <(sort -u "$list")
rm -f "$list"

if [ ${#apps[@]} -eq 0 ]; then
  echo "Godot 를 찾지 못했습니다. ~/Game/zerosum 에서 setup/install.sh 를 실행하면 /Applications/Godot.app 에 하나 설치합니다."; exit 0
fi

# 2) 남길 것 고르기: /Applications/Godot.app 이 4.7 이면 그것, 아니면 4.7 중 첫 번째
keep=""
if [ -e "$KEEP_TARGET" ] && is_godot47 "$KEEP_TARGET"; then keep="$KEEP_TARGET"; fi
if [ -z "$keep" ]; then
  for a in "${apps[@]}"; do if is_godot47 "$a"; then keep="$a"; break; fi; done
fi

echo "찾은 Godot ${#apps[@]}개:"
i=1
for a in "${apps[@]}"; do
  v="$(godot_version_of "$a")"; s="$(du -sh "$a" 2>/dev/null | cut -f1)"
  mark="휴지통으로"; [ "$a" = "$keep" ] && mark="남김"
  printf "  %d) [%s] %s  (버전 %s, %s)\n" "$i" "$mark" "$a" "${v:-알 수 없음}" "${s:-?}"
  i=$((i+1))
done
if [ -z "$keep" ]; then
  echo "!! 4.7 버전이 없어 아무것도 지우지 않습니다. ~/Game/zerosum 에서 setup/install.sh 를 먼저 실행하세요." >&2; exit 1
fi
[ "$keep" != "$KEEP_TARGET" ] && echo "  → 남길 것을 $KEEP_TARGET 로 옮깁니다."
if [ ${#apps[@]} -eq 1 ] && [ "$keep" = "$KEEP_TARGET" ]; then echo "이미 하나만 있습니다."; exit 0; fi

printf "진행할까요? [y/N] "
ans="${CLEANUP_YES:-}"   # CLEANUP_YES=y 이면 묻지 않음
if [ -z "$ans" ]; then if [ -t 0 ]; then read -r ans; else read -r ans < /dev/tty || true; fi; fi
case "$ans" in y|Y|yes|YES) ;; *) echo "취소했습니다. 아무것도 바꾸지 않았습니다."; exit 0 ;; esac

trash="$HOME/.Trash"; mkdir -p "$trash"
to_trash() {
  local src="$1" base dst
  base="$(basename "$src")"; dst="$trash/$base"
  [ -e "$dst" ] && dst="$trash/${base%.app} $(date +%H%M%S).${base##*.}"
  mv "$src" "$dst" && echo "  휴지통: $src"
}
# 남길 것을 먼저 제자리로 (기존 /Applications/Godot.app 이 다른 버전이면 그것부터 휴지통)
if [ "$keep" != "$KEEP_TARGET" ]; then
  [ -e "$KEEP_TARGET" ] && to_trash "$KEEP_TARGET"
  if mv "$keep" "$KEEP_TARGET" 2>/dev/null; then
    echo "  이동: $keep → $KEEP_TARGET"; keep="$KEEP_TARGET"
  else
    echo "  ($KEEP_TARGET 로 옮길 권한이 없어 $keep 에 그대로 둡니다)"
  fi
fi
for a in "${apps[@]}"; do
  [ -e "$a" ] || continue
  [ "$a" = "$keep" ] && continue
  [ "$a" = "$KEEP_TARGET" ] && continue
  to_trash "$a"
done
# 빈 _engine 폴더 정리
rmdir "$GAME_DIR/_engine" 2>/dev/null || true
echo "완료. 남은 Godot: $keep"
echo "게임 실행: Finder 에서 ~/Game/zerosum/play.command 더블클릭 (자동으로 이 Godot 를 씁니다)"
