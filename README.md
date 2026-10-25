# RT Zerosum — 전투 플레이어블 프로토타입 (Godot 4.7)

횡스크롤 턴제 6인 AP 전투 프로토타입. `docs/design/PROTOTYPE_GDD_v1_0.md` 의 확정 규칙과 임시값을 구현했고,
**같은 전투 규칙 위에 2D 표현(원화 + 구역 마스크 셰이더)과 3D 표현(셀 셰이더 + 실광원) 두 가지 뷰**를 올려
그래픽 방향(2D vs 3D)을 비교·결정할 수 있게 했습니다. 비교 결과는 `docs/2D_vs_3D_comparison.md` 참조.

## 실행
1. Godot 4.7 (stable) 로 이 폴더를 열고 F5. 메인 씬 `scenes/main_menu.tscn`.
2. 메뉴에서 **표현 모드(2D/3D)**, 조명 프리셋(G1~G4), 선공(동전/아군 기습/적 매복), 시드를 고른 뒤 편성 → 전투.
3. 전투 중 단축키: `1~4` 조명 프리셋 즉시 교체 · `Tab` 2D↔3D 즉시 전환 · `F1` 디버그 패널 · `F2` HUD 숨김 · `R` 재시작 · `Space` 턴 종료 · 우클릭 취소.

렌더러는 `gl_compatibility` 로 두었습니다(저사양/소프트웨어 렌더 검증 포함). Forward+ 로 바꿔도 셰이더는 그대로 동작합니다.

## Skeleton2D 리그 (2D 확정 후 비용 테스트)
사용자 제공 원화 1장을 `tools/rig_cutter.py` 로 17개 파츠 + 16개 본 + 파츠별 구역 마스크로 잘라 `assets/sprites/rig_hero/` 에 두고,
`RiggedUnit2D` 가 rig.json 으로 Bone2D 트리와 애니메이션(idle/attack/hit/heal/death)을 만든다. 아군 '라온' 슬롯이 이 캐릭터다.
비용 측정 결과와 파이프라인은 `docs/skeleton2d_cost.md`, 벤치는 메뉴의 "리그 벤치" 또는
`++ --scene=bench --count=48 --rig=1` (B 본 표시, Tab 평면↔리그, +/- 인원).

## 규칙 테스트 (헤드리스)
```
godot --headless --path . --import          # 최초 1회 (클래스 캐시 생성)
godot --headless --path . -s tests/run_tests.gd
```
GDD 8절 "필수 검증 사례" 10개 그룹 59개 체크를 모두 통과합니다 (선공 특례, 2라운드 미적용, 동률 아군/레벨/원거리 우선,
AP 상한 버림/이월/0 자동 종료, 이동/교환 AP 1, 무기 변경 AP 1, AP 부족/무효 대상 시 AP 미소모, 재시작 초기화, 시드 재현성).

## 스크린샷 일괄 렌더
```
GODOT=/path/to/godot tools/render_shots.sh docs/screenshots      # Xvfb + Mesa 소프트웨어 렌더
```
CLI 인자(`++` 뒤): `--scene=battle|formation|result|menu --mode=2d|3d --preset=g1..g4 --shot=경로 --autoplay=aim|move|fight:N --hud=0`.

## 폴더
```
scenes/            main_menu, formation, battle_2d, battle_3d, battle_hud, result
scripts/battle/    규칙 계층 (표현 비의존): unit_data, action_data, unit_runtime, slot_manager,
                   turn_scheduler, ap_component, target_validator, action_resolver, enemy_ai, battle_controller
scripts/presentation/  battle_view_base (공통 인터페이스), battle_view_2d + unit_sprite_2d + rigged_unit_2d + slot_marker_2d,
                   battle_view_3d + unit_model_3d, lighting_presets
scripts/ui/        battle_hud, main_menu, formation, result
scripts/data/      test_roster (임시 테스트 데이터 12인 + 행동 7종)
shaders/           cel_zoned_lighting (2D, v0.3), flat_zone_fill, cel_3d, outline_3d, unlit_3d
assets/sprites/    생성된 캐릭터/무기 스프라이트 + 구역 마스크 (_mask_r/_mask_l) + manifest.json
assets/textures/   배경 플레이트 + 마스크, 3D 얼굴 데칼
tools/             gen_sprites.py (원화·마스크 생성기), rig_cutter.py (원화→리그 파츠), render_shots.sh
tests/             run_tests.gd
docs/              design/ (기획서 사본), screenshots/, 2D_vs_3D_comparison.md
```

## 데이터 흐름
`BattleController` 가 상태 머신(PREPARE → INITIATIVE → ROUND_START → ACTOR_START → PLAYER_COMMAND/ENEMY_AI → ACTION_RESOLVE → …)을 돌리며
신호만 내보내고, `BattleView2D`/`BattleView3D` 는 같은 `BattleViewBase` 인터페이스로 그 신호를 연출로 바꿉니다.
모든 행동은 `can_execute → pay_ap → resolve → emit_event` 한 경로(`BattleController._execute`)를 지납니다.

## 임시 에셋 주의
캐릭터/배경은 `tools/gen_sprites.py` 가 도형으로 생성한 **검증용 대체 원화**입니다. 레퍼런스 이미지는 포함하지 않았습니다.
