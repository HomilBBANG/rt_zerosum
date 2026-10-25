#!/usr/bin/env bash
# RT Zerosum 실행 (macOS / Linux). "./play.sh edit" 이면 Godot 에디터로 연다.
cd "$(dirname "$0")"
if [ -x "_engine/Godot.app/Contents/MacOS/Godot" ]; then
  GODOT="_engine/Godot.app/Contents/MacOS/Godot"
elif [ -x "_engine/Godot_v4.7-stable_linux.x86_64" ]; then
  GODOT="_engine/Godot_v4.7-stable_linux.x86_64"
elif command -v godot >/dev/null 2>&1; then
  GODOT="godot"
else
  echo "Godot 4.7 이 없습니다. setup/install.sh 를 먼저 실행하세요." >&2; exit 1
fi
if [ ! -d ".godot/imported" ]; then
  echo "첫 실행: 리소스 임포트 중 (1~2분)..."
  "$GODOT" --headless --path . --import >/dev/null 2>&1 || true
fi
if [ "${1:-}" = "edit" ]; then
  exec "$GODOT" --path . --editor
else
  exec "$GODOT" --path .
fi
