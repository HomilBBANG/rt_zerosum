#!/usr/bin/env bash
# RT Zerosum 실행 (macOS / Linux). "./play.sh edit" 이면 Godot 에디터로 연다.
cd "$(dirname "$0")"
. setup/godot_find.sh
if ! GODOT="$(find_godot47 "$PWD")"; then
  echo "Godot 4.7 이 없습니다. setup/install.sh 를 먼저 실행하세요." >&2; exit 1
fi
# git pull 로 새 원화·리그가 들어오면 실행 전에 임포트가 필요하다.
# 마지막으로 임포트한 커밋을 .godot/last_import_rev 에 적어 두고, 커밋이 바뀌었을 때만 다시 임포트 (바뀐 파일만 처리).
REV="$(git rev-parse HEAD 2>/dev/null || echo nogit)"
STAMP=".godot/last_import_rev"
if [ ! -d ".godot/imported" ] || [ "$REV" = "nogit" ] || [ "$(cat "$STAMP" 2>/dev/null)" != "$REV" ]; then
  echo "리소스 임포트 중 (업데이트 후 첫 실행, 최대 1~2분)..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
  mkdir -p .godot && echo "$REV" > "$STAMP"
fi
if [ "${1:-}" = "edit" ]; then
  exec "$GODOT" --path . --editor
else
  exec "$GODOT" --path .
fi
