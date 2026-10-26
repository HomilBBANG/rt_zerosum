# RT Zerosum — 전투 플레이어블 프로토타입 (Godot 4.7)

횡스크롤 턴제 6인 AP 전투 프로토타입. `docs/design/PROTOTYPE_GDD_v1_0.md` 의 확정 규칙과 임시값을 구현했고,
**같은 전투 규칙 위에 2D 표현(원화 + 구역 마스크 셰이더)과 3D 표현(셀 셰이더 + 실광원) 두 가지 뷰**를 올려
그래픽 방향(2D vs 3D)을 비교·결정할 수 있게 했습니다. 비교 결과는 `docs/2D_vs_3D_comparison.md` 참조.

## 설치 (노트북·데스크톱 공통, 명령 한 줄)
각 기기의 `/Users/eunjikim/Game/zerosum` (= `~/Game/zerosum`, Windows 는 `C:\Users\<이름>\Game\zerosum`)에 프로젝트를 받고,
Godot 4.7 이 없을 때만 macOS 는 `/Applications/Godot.app` 하나에 설치해 바로 실행합니다(이미 있으면 재사용). 저장소가 공개라 GitHub 로그인은 필요 없습니다.

**Windows** — 시작 메뉴에서 PowerShell 을 열고 붙여넣기:
```powershell
irm https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/install_windows.ps1 | iex
```
설치가 끝나면 바탕화면에 **RT Zerosum** 바로가기가 생깁니다. 이후 실행은 바로가기 또는 `Game\zerosum\play.bat`.

**macOS (노트북·컴퓨터 공통)** — 터미널에 붙여넣기:
```bash
curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/install.sh | bash
```
이후 실행은 Finder 에서 `Game/zerosum/play.command` 더블클릭, 또는 `~/Game/zerosum/play.sh`.
`~/Game/zerosum` 폴더가 이미 있고 다른 파일이 들어 있어도 지우지 않고 그 자리에 연결합니다. 저장소 파일과 이름이 겹치는 기존 파일(예: Godot 가 만든 `.gitignore`)은 `_backup_before_install_날짜/` 폴더로 옮겨 둡니다.

**Godot 가 여러 개 깔렸을 때**: 아래 명령이 Mac 의 Godot 를 모두 찾아 목록을 보여주고, y 를 입력하면 4.7 하나만
`/Applications/Godot.app` 에 남기고 나머지는 휴지통으로 옮깁니다(Finder 휴지통에서 복구 가능).
```bash
curl -fsSL https://raw.githubusercontent.com/HomilBBANG/rt_zerosum/main/setup/cleanup_godot.sh | bash
```

**업데이트**: 프로젝트 폴더에서 `git pull` 만 하면 됩니다 → 그다음 평소처럼 `play.command` / `play.sh` / `play.bat` 실행.
새 원화·리그가 들어온 커밋이면 실행 스크립트가 알아서 리소스를 다시 임포트합니다(커밋이 바뀐 첫 실행에만, 최대 1~2분).
```bash
cd ~/Game/zerosum && git pull
```
git 이 없는 설치(zip)는 같은 설치 명령을 다시 실행하면 최신으로 받아옵니다.
**에디터로 열기**: `play.bat edit` / `./play.sh edit`.
**다른 폴더에 설치**: macOS `curl ... | GAME_DIR=/경로 bash`, Windows `$env:GAME_DIR="D:\Game"` 를 먼저 지정.

> git 이 설치돼 있으면 두 기기 모두 `git pull` 로 같은 코드를 맞출 수 있습니다. 한쪽에서 수정한 뒤 다른 쪽에서 받으려면
> 수정한 기기에서 `git push` 할 권한(HomilBBANG/rt_zerosum 저장소 협업자)이 필요합니다.

## 실행
1. 위 설치 스크립트를 썼다면 `play.bat` / `play.sh`. 직접 설치한 Godot 4.7 (stable) 로 이 폴더를 열어 F5 해도 됩니다. 메인 씬 `scenes/main_menu.tscn`.
2. 메뉴에서 조명 프리셋(G1~G4), 선공(동전/아군 기습/적 매복), 시드를 고른 뒤 편성 → 전투.
3. 화면: 창은 **QHD(2560×1440 픽셀)** 로 고정해 그 해상도로 렌더합니다(모니터가 작으면 16:9 로 맞춰 줄임). `F11` 전체 화면.
4. 전투 시작: 일반 전투(동전)는 화면 아래에서 금화가 튀어 올라 오른쪽으로 돌며 떨어집니다 — **고양이 면(앞면) = 아군 선공, 매끈한 면(뒷면) = 적 선공**.
   상단에는 행동 순서가 초상화로 나오고(마우스를 올리면 이름), 차례인 캐릭터의 초상화가 30% 커집니다. 글꼴은 Pretendard.
5. 전투 중 단축키: `1~4` 조명 프리셋 즉시 교체 · `F1` 디버그 패널 · `F2` HUD 숨김 · `F3` 캐릭터 림 라인 켜기/끄기 · `R` 재시작 · `Space` 턴 종료 · 우클릭 취소.

렌더러는 `gl_compatibility` 로 두었습니다(저사양/소프트웨어 렌더 검증 포함). Forward+ 로 바꿔도 셰이더는 그대로 동작합니다.

## 카메라 (2D 전투)
2D 전투는 정면 평면이 아니라 **뒤로 물러나 40° 내려다보는 가상 카메라**로 구성됩니다. `tools/gen_sprites.py` 의 `CAMERA`
(피치 40°, 거리 15m, 세로 화각 32°, 화면 중심 y 480 — 벽이 더 보이고 바닥이 덜 보이게 구도를 위로)로 배경(바닥 원근·벽·소품·빛 영역 마스크)을 그리고, 같은 값이
`manifest.json` 의 `camera` 로 저장되어 `BattleView2D` 가 슬롯 위치와 캐릭터 크기(원근 배율)를 계산합니다.
각도나 거리를 바꾸려면 `CAMERA` 를 수정하고 `python3 tools/gen_sprites.py` 를 다시 실행하면 배경과 배치가 함께 바뀝니다.
3D 뷰도 같은 각도(40°)로 맞춰 두었습니다.

## 전투 편성 (게임 기본)
게임은 **사용자 제공 원화 캐릭터만** 배치합니다 (6대2, `TestRoster.build_provided_*`):
- 아군(사람 6인): 단(돌격병 185cm, 전방)·키라(돌격병 175cm, 전방)·이선(소총수 178cm, 중앙)·하나(돌격소총수 176.8cm, 중앙)·앨마(의무병 166cm, 후방)·니키타(저격수 168cm, 후방)
- 적(괴물, 적으로만 등장): 구울(2.4m) — **전방+중앙 두 칸 차지** (`UnitData.row_span = 2`), 늑대(4m) — 후방 한 칸
  두 칸 괴물은 살아 있는 동안 전방을 막고(근접은 괴물부터), 자리 이동·교환을 하지 않으며, 두 칸의 가운데에 선다.
도형으로 생성한 12인(`build_allies/build_enemies`)은 규칙 테스트와 리그 벤치에서만 씁니다.
새 캐릭터 추가: 원화를 `assets/source/` 에 두고(검정 배경 원화는 먼저 `python3 tools/remove_black_bg.py 입력 출력` 으로 투명화) `tools/rig_cutter.py` 의 `CHARACTERS` 에 본·파츠 좌표를 추가 →
`python3 tools/rig_cutter.py <id>` → 임포트 후 `tools/set_mipmaps.py` → 로스터에 `sprite_id: "<id>"`, `height_cm` 으로 등록.
캐릭터 키는 `rig.json` 의 `figure_px`(원화 정수리~발 픽셀)를 화면 230px = 175cm 기준으로 환산해 2D·3D 모두에 반영됩니다.

## 배경 3D + 캐릭터 2D (하이브리드, 기본)
2D 전투의 배경은 3D 방(창·문 밖 스폿라이트, 하드 섀도우, 셀 셰이더)을 2D 가상 카메라와 **같은 투영**으로 렌더한 텍스처입니다
(`BattleView3D.configure_as_background` / `set_view`, QHD 해상도로 카메라가 움직이거나 위치·프리셋이 바뀔 때만 다시 렌더).
캐릭터는 2D 리그 그대로이고, 자기 위치에 실제로 닿는 빛(원뿔 범위, 창·문 개구부 통과, 문짝 가림)을 `light_probe` 로 계산해 명암을 정합니다.
- 빛 쪽 얼굴·몸을 그 광원색으로 밝히고 반대편은 셀 그림자.
- 빛이 뒤(벽의 창·문)에서 오면 **빛 쪽 가장자리에 같은 색 림**을 더함(반대 방향 마스크의 림 구역 사용). 반대편 림은 그쪽에서 실제 빛이 올 때만.
- 보이지 않는 그림자 대리 물체로 캐릭터 그림자가 바닥에 드리워집니다.
이전 2D 원화 배경은 `--bg=2d` 로 볼 수 있습니다. 투영 확인용 `--bgdebug=1`(슬롯 위치 빨간 점).

## 전투 카메라
전투가 시작되면 먼저 전장 전체 구도를 약 1초 보여준 뒤 2배로 줌인하고, 이후 차례가 온 캐릭터의 몸 중심을 화면 가운데
(상단 바와 하단 명령 패널 사이 중앙)로 옮깁니다. 3D 배경은 2D 카메라의 위치·줌을 그대로 따라 다시 그려서, 줌을 해도 흐려지지 않고
화면 가장자리 캐릭터도 정확히 중앙에 올 수 있습니다. 배경 밖은 보이지 않게 제한합니다. 값은 `battle_view_2d.gd` 의 `CAM_*` 상수.
스크린샷 CLI 는 기본으로 인트로를 건너뛰며 `--intro=1`(재생), `--intro=hold`(전체 구도에서 멈춤)로 바꿀 수 있습니다.

## Skeleton2D 리그 (2D 확정 후 비용 테스트)
사용자 제공 원화 1장을 `tools/rig_cutter.py` 로 17개 파츠 + 16개 본 + 파츠별 구역 마스크로 잘라 `assets/sprites/rig_<id>/` 에 두고,
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
GODOT=/path/to/godot tools/render_shots.sh docs/screenshots      # Xvfb + Mesa 소프트웨어 렌더, QHD 출력
```
CLI 인자(`++` 뒤): `--scene=battle|formation|result|menu --mode=2d|3d --preset=g1..g4 --shot=경로 --autoplay=aim|move|fight:N --hud=0`.
디버그: `--charview=1`(캐릭터 원화를 조명 없이 출력), `--outline=0`(외곽선 끔), `--rim=0`(림 끔).

## 폴더
```
scenes/            main_menu, formation, battle_2d, battle_3d, battle_hud, result
scripts/battle/    규칙 계층 (표현 비의존): unit_data, action_data, unit_runtime, slot_manager,
                   turn_scheduler, ap_component, target_validator, action_resolver, enemy_ai, battle_controller
scripts/presentation/  battle_view_base (공통 인터페이스), battle_view_2d + unit_sprite_2d + rigged_unit_2d + slot_marker_2d,
                   battle_view_3d + unit_model_3d, lighting_presets
scripts/ui/        battle_hud, main_menu, formation, result
scripts/data/      test_roster (임시 테스트 데이터 12인 + 행동 7종)
shaders/           cel_zoned_lighting (2D 배경, v0.3), cel_character (2D 캐릭터), outline_group (캐릭터 외곽선), flat_zone_fill, cel_3d, outline_3d, unlit_3d
assets/sprites/    생성된 캐릭터/무기 스프라이트 + 구역 마스크 (_mask_r/_mask_l) + manifest.json
assets/textures/   배경 플레이트 + 마스크, 3D 얼굴 데칼
setup/             install_windows.ps1, install.sh (기기 설치), play.bat / play.sh / play.command (루트, 실행)
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
