# Godot 4.7 위치 찾기 (install.sh / play.sh / cleanup_godot.sh 공용). source 해서 사용.
# find_godot47 → 찾으면 실행 파일 경로를 출력하고 0 반환.
GODOT_WANT="4.7"

godot_version_of() {   # $1 = .app 경로 또는 실행 파일
  local p="$1" v=""
  if [ -d "$p" ] && [ -f "$p/Contents/Info.plist" ]; then
    v="$(defaults read "$p/Contents/Info" CFBundleShortVersionString 2>/dev/null || true)"
    [ -z "$v" ] && v="$(plutil -extract CFBundleShortVersionString raw "$p/Contents/Info.plist" 2>/dev/null || true)"
    [ -z "$v" ] && [ -x "$p/Contents/MacOS/Godot" ] && v="$("$p/Contents/MacOS/Godot" --version 2>/dev/null | head -1)"
  elif [ -x "$p" ]; then
    v="$("$p" --version 2>/dev/null | tail -1)"
  fi
  echo "$v"
}

godot_exe_of() {       # .app → 내부 실행 파일, 실행 파일 → 그대로
  if [ -d "$1" ]; then echo "$1/Contents/MacOS/Godot"; else echo "$1"; fi
}

is_godot47() { case "$(godot_version_of "$1")" in "$GODOT_WANT"|"$GODOT_WANT".*) return 0 ;; *) return 1 ;; esac; }

find_godot47() {
  local game_dir="${1:-}" c
  for c in "${GODOT:-}" "/Applications/Godot.app" "$HOME/Applications/Godot.app" \
           "${game_dir:+$game_dir/_engine/Godot.app}" \
           "${game_dir:+$game_dir/_engine/Godot_v4.7-stable_linux.x86_64}" \
           "$(command -v godot 2>/dev/null || true)"; do
    [ -n "$c" ] && [ -e "$c" ] || continue
    if is_godot47 "$c"; then godot_exe_of "$c"; return 0; fi
  done
  return 1
}
