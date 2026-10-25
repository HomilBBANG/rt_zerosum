#!/usr/bin/env bash
# 2D/3D × 조명 프리셋 × 상태 스크린샷 일괄 렌더 (Xvfb + Mesa llvmpipe 소프트웨어 렌더).
# 사용: GODOT=/path/to/godot tools/render_shots.sh [출력폴더]
set -u
GODOT="${GODOT:-godot}"
OUT="${1:-docs/screenshots}"
mkdir -p "$OUT"
cd "$(dirname "$0")/.."
run() { # mode preset state name extra...
  local mode="$1" preset="$2" state="$3" name="$4"; shift 4
  timeout 150 xvfb-run -a -s "-screen 0 2560x1440x24" "$GODOT" --path . --rendering-driver opengl3 --quit-after 1500 \
    --log-file "/tmp/rt_shot_${name}.log" ++ --mode="$mode" --preset="$preset" --shot="$PWD/$OUT/$name.png" --enemy_delay=0.15 "$@" > /dev/null 2>&1
  echo "[$name] $(grep -c 'SCRIPT ERROR' /tmp/rt_shot_${name}.log 2>/dev/null) script errors"
}
for mode in ${MODES:-2d 3d}; do
  for preset in g1 g2 g3 g4; do
    run $mode $preset aim "${mode}_${preset}_aim" --scene=battle --autoplay=aim --frames=45 &
    run $mode $preset fight "${mode}_${preset}_fight" --scene=battle --autoplay=fight:5 --frames=30 &
    wait
  done
  run $mode g1 move "${mode}_g1_move" --scene=battle --autoplay=move --frames=45 &
  run $mode g1 nohud "${mode}_g1_nohud" --scene=battle --autoplay=aim --frames=45 --hud=0 &
  wait
done
[ "${UI:-1}" = "1" ] && run 2d g1 menu "ui_menu" --scene=menu --frames=10 &
[ "${UI:-1}" = "1" ] && run 2d g1 formation "ui_formation" --scene=formation --frames=10 &
[ "${UI:-1}" = "1" ] && run 2d g1 result "ui_result" --scene=result --frames=10 &
wait
echo done
