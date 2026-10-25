#!/usr/bin/env bash
# RT Zerosum 설치 (macOS / Linux): ~/Game/zerosum (/Users/<이름>/Game/zerosum) 에 프로젝트를 받고, Godot 4.7 이 없을 때만
# /Applications/Godot.app 에 하나 설치한 뒤 실행. 이미 있는 Godot 4.7 은 그대로 재사용한다.
# 사용:  curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/install.sh | bash
# 옵션(환경변수): GAME_DIR=설치폴더  GAME_BRANCH=브랜치  NO_RUN=1(설치만)
set -euo pipefail
REPO="https://github.com/HomilBBANG/rt_zerosum.git"
BRANCH="${GAME_BRANCH:-main}"
DIR="${GAME_DIR:-$HOME/Game/zerosum}"
GODOT_VER="4.7-stable"
BASE="https://github.com/godotengine/godot-builds/releases/download/${GODOT_VER}"

echo "== RT Zerosum 설치: $DIR (브랜치 $BRANCH)"
# 예전 기본 위치(~/Game 바로 아래)에 받아 둔 적이 있으면 알려준다 (자동으로 지우지 않음)
PARENT="$(dirname "$DIR")"
if [ "$PARENT" != "$DIR" ] && [ -d "$PARENT/.git" ] && git -C "$PARENT" remote get-url origin 2>/dev/null | grep -q "rt_zerosum"; then
  echo "!! $PARENT 에도 예전에 받은 같은 프로젝트가 있습니다. 새 위치는 $DIR 입니다."
  echo "   필요 없으면 $PARENT 안의 프로젝트 파일(.git, assets, scenes, scripts 등)을 정리하세요. 이 스크립트는 지우지 않습니다."
fi
# 저장소 파일과 이름이 겹치는 '추적되지 않은 기존 파일'을 백업 폴더로 옮긴다 (지우지 않음)
backup_conflicts() {
  local ref="$1" bdir="" f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ -e "$DIR/$f" ] && ! git -C "$DIR" ls-files --error-unmatch -- "$f" >/dev/null 2>&1; then
      [ -z "$bdir" ] && bdir="$DIR/_backup_before_install_$(date +%Y%m%d_%H%M%S)"
      mkdir -p "$bdir/$(dirname "$f")"
      mv "$DIR/$f" "$bdir/$f"
      echo "   백업: $f → $(basename "$bdir")/$f"
    fi
  done < <(git -C "$DIR" ls-tree -r --name-only "$ref")
  [ -n "$bdir" ] && echo "-- 이름이 겹치는 기존 파일을 $bdir 로 옮겼습니다."
  return 0
}

connect_in_place() {
  echo "-- $DIR 에 기존 파일이 있어 그 자리에 연결합니다 (겹치는 파일만 백업 폴더로 이동)"
  [ -d "$DIR/.git" ] || git -C "$DIR" init -q
  git -C "$DIR" remote add origin "$REPO" 2>/dev/null || git -C "$DIR" remote set-url origin "$REPO"
  git -C "$DIR" fetch -q origin "$BRANCH"
  backup_conflicts "origin/$BRANCH"
  git -C "$DIR" checkout -q -B "$BRANCH" --track "origin/$BRANCH"
}

HAS_GIT=0; git --version >/dev/null 2>&1 && HAS_GIT=1   # macOS 의 /usr/bin/git 껍데기(개발도구 미설치)는 여기서 걸러짐
if [ -d "$DIR/.git" ] && [ $HAS_GIT = 1 ] && git -C "$DIR" rev-parse --verify -q HEAD >/dev/null; then
  echo "-- 이미 있음: 최신으로 업데이트"
  git -C "$DIR" remote set-url origin "$REPO" 2>/dev/null || git -C "$DIR" remote add origin "$REPO"
  git -C "$DIR" fetch -q origin "$BRANCH"
  if [ "$(git -C "$DIR" rev-parse --abbrev-ref HEAD)" != "$BRANCH" ]; then
    backup_conflicts "origin/$BRANCH"
    git -C "$DIR" checkout -q -B "$BRANCH" --track "origin/$BRANCH"
  else
    git -C "$DIR" pull -q --ff-only origin "$BRANCH"
  fi
elif [ -d "$DIR/.git" ] && [ $HAS_GIT = 1 ]; then
  # 이전 실행이 중간에 멈춰 커밋 없는 .git 만 남은 경우
  connect_in_place
elif [ $HAS_GIT = 1 ]; then
  if [ -d "$DIR" ] && [ -n "$(ls -A "$DIR" 2>/dev/null)" ]; then
    connect_in_place
  else
    mkdir -p "$(dirname "$DIR")"
    git clone -b "$BRANCH" "$REPO" "$DIR"
  fi
else
  echo "-- git 이 없어 zip 으로 받습니다 (업데이트하려면 다시 실행. xcode-select --install 로 git 을 설치하면 pull 로 업데이트됩니다)"
  tmp="$(mktemp -d)"
  curl -fL -o "$tmp/src.zip" "https://codeload.github.com/HomilBBANG/rt_zerosum/zip/refs/heads/${BRANCH}"
  unzip -q "$tmp/src.zip" -d "$tmp"
  mkdir -p "$DIR"
  cp -R "$tmp"/rt_zerosum-*/. "$DIR"/
  rm -rf "$tmp"
fi

. "$DIR/setup/godot_find.sh"
if BIN="$(find_godot47 "$DIR")"; then
  echo "-- 이미 설치된 Godot 4.7 사용: $BIN (새로 받지 않음)"
else
  case "$(uname -s)" in
    Darwin)
      echo "-- Godot ${GODOT_VER} (macOS) 다운로드 → /Applications/Godot.app"
      tmpz="$(mktemp -d)"
      curl -fL -o "$tmpz/godot.zip" "$BASE/Godot_v${GODOT_VER}_macos.universal.zip"
      unzip -q -o "$tmpz/godot.zip" -d "$tmpz"
      if [ -e /Applications/Godot.app ]; then mv /Applications/Godot.app "$HOME/.Trash/Godot (old $(date +%H%M%S)).app"; fi
      if mv "$tmpz/Godot.app" /Applications/Godot.app 2>/dev/null; then
        BIN="/Applications/Godot.app/Contents/MacOS/Godot"
      else
        mkdir -p "$HOME/Applications" && mv "$tmpz/Godot.app" "$HOME/Applications/Godot.app"
        BIN="$HOME/Applications/Godot.app/Contents/MacOS/Godot"
      fi
      xattr -dr com.apple.quarantine "$(dirname "$(dirname "$(dirname "$BIN")")")" 2>/dev/null || true
      rm -rf "$tmpz" ;;
    Linux)
      mkdir -p "$DIR/_engine"
      BIN="$DIR/_engine/Godot_v${GODOT_VER}_linux.x86_64"
      echo "-- Godot ${GODOT_VER} (Linux) 다운로드"
      curl -fL -o "$DIR/_engine/godot.zip" "$BASE/Godot_v${GODOT_VER}_linux.x86_64.zip"
      unzip -q -o "$DIR/_engine/godot.zip" -d "$DIR/_engine" && rm "$DIR/_engine/godot.zip"
      chmod +x "$BIN" ;;
    *) echo "!! 지원하지 않는 OS: $(uname -s). Windows 는 setup/install_windows.ps1 을 쓰세요." >&2; exit 1 ;;
  esac
fi

chmod +x "$DIR/play.sh" "$DIR/play.command" 2>/dev/null || true
echo "-- 첫 리소스 임포트 (1~2분)"
"$BIN" --headless --path "$DIR" --import >/dev/null 2>&1 || true
echo "== 설치 완료. 다음부터는 $DIR/play.sh (macOS 는 play.command 더블클릭) 로 실행합니다."
if [ "${NO_RUN:-0}" != "1" ]; then
  "$DIR/play.sh"
fi
