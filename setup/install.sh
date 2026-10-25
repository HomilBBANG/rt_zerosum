#!/usr/bin/env bash
# RT Zerosum 설치 (macOS / Linux): ~/game 에 프로젝트를 받고 Godot 4.7 을 _engine/ 에 내려받은 뒤 실행.
# 사용:  curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/claude/clever-keller-maq0u6/setup/install.sh | bash
# 옵션(환경변수): GAME_DIR=설치폴더  GAME_BRANCH=브랜치  NO_RUN=1(설치만)
set -euo pipefail
REPO="https://github.com/HomilBBANG/rt_zerosum.git"
BRANCH="${GAME_BRANCH:-claude/clever-keller-maq0u6}"
DIR="${GAME_DIR:-$HOME/game}"
GODOT_VER="4.7-stable"
BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}"

echo "== RT Zerosum 설치: $DIR (브랜치 $BRANCH)"
if [ -d "$DIR/.git" ]; then
  echo "-- 이미 있음: 최신으로 업데이트"
  git -C "$DIR" fetch origin "$BRANCH"
  git -C "$DIR" checkout -q "$BRANCH"
  git -C "$DIR" pull --ff-only origin "$BRANCH"
elif command -v git >/dev/null 2>&1; then
  if [ -e "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
    echo "!! $DIR 에 다른 파일이 있습니다. 비우거나 GAME_DIR 로 다른 폴더를 지정하세요." >&2; exit 1
  fi
  git clone -b "$BRANCH" "$REPO" "$DIR"
else
  echo "-- git 이 없어 zip 으로 받습니다 (업데이트하려면 다시 실행)"
  tmp="$(mktemp -d)"
  curl -fL -o "$tmp/src.zip" "https://codeload.github.com/HomilBBANG/rt_zerosum/zip/refs/heads/${BRANCH}"
  unzip -q "$tmp/src.zip" -d "$tmp"
  mkdir -p "$DIR"
  cp -R "$tmp"/rt_zerosum-*/. "$DIR"/
  rm -rf "$tmp"
fi

mkdir -p "$DIR/_engine"
case "$(uname -s)" in
  Darwin)
    BIN="$DIR/_engine/Godot.app/Contents/MacOS/Godot"
    if [ ! -x "$BIN" ]; then
      echo "-- Godot ${GODOT_VER} (macOS) 다운로드"
      curl -fL -o "$DIR/_engine/godot.zip" "$BASE/Godot_v${GODOT_VER}_macos.universal.zip"
      unzip -q -o "$DIR/_engine/godot.zip" -d "$DIR/_engine" && rm "$DIR/_engine/godot.zip"
      xattr -dr com.apple.quarantine "$DIR/_engine/Godot.app" 2>/dev/null || true
    fi ;;
  Linux)
    BIN="$DIR/_engine/Godot_v${GODOT_VER}_linux.x86_64"
    if [ ! -x "$BIN" ]; then
      echo "-- Godot ${GODOT_VER} (Linux) 다운로드"
      curl -fL -o "$DIR/_engine/godot.zip" "$BASE/Godot_v${GODOT_VER}_linux.x86_64.zip"
      unzip -q -o "$DIR/_engine/godot.zip" -d "$DIR/_engine" && rm "$DIR/_engine/godot.zip"
      chmod +x "$BIN"
    fi ;;
  *) echo "!! 지원하지 않는 OS: $(uname -s). Windows 는 setup/install_windows.ps1 을 쓰세요." >&2; exit 1 ;;
esac

chmod +x "$DIR/play.sh" "$DIR/play.command" 2>/dev/null || true
echo "-- 첫 리소스 임포트 (1~2분)"
"$BIN" --headless --path "$DIR" --import >/dev/null 2>&1 || true
echo "== 설치 완료. 다음부터는 $DIR/play.sh (macOS 는 play.command 더블클릭) 로 실행합니다."
if [ "${NO_RUN:-0}" != "1" ]; then
  "$DIR/play.sh"
fi
