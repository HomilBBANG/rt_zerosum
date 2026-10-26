extends Node
## Autoload "Game": 씬 전환, 전역 설정(2D/3D 모드, 조명 프리셋, 선공, 시드, 편성), CLI 스크린샷 지원.

const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_FORMATION := "res://scenes/formation.tscn"
const SCENE_BATTLE_2D := "res://scenes/battle_2d.tscn"
const SCENE_BATTLE_3D := "res://scenes/battle_3d.tscn"
const SCENE_RESULT := "res://scenes/result.tscn"
const SCENE_BENCH := "res://scenes/rig_bench.tscn"

var mode: String = "2d"            # 캐릭터는 2D 확정 (3D 전환 제거, 2026-10-26). 3D 씬은 비교 기록용으로만 남김
var preset: String = "g1"          # LightingPresets 키
var ambush: String = "none"        # "none" | "ally" | "enemy"
var seed_value: int = 12345
var formation: Array = []          # [{unit_id, row, index}]
var allies: Array[UnitData] = []
var enemies: Array[UnitData] = []
var actions: Dictionary = {}
var restart_count: int = 0
var rim_enabled: bool = true      # 캐릭터 림 라인: 사용 확정(2026-10-25). F3 토글·CLI --rim=0 은 비교·디버그용
var last_result: Dictionary = {}
var cli: Dictionary = {}
## 밸런스 데이터 (data/balance.xlsx). 실행 중 파일이 저장되면 다시 읽어 즉시 반영 → data_reloaded
var data: GameData = null
var stage_id: String = ""
signal data_reloaded(warnings: PackedStringArray)
var _balance_mtime: int = 0
var _poll_t: float = 0.0
const SCENE_AI_EDITOR := "res://scenes/ai_editor.tscn"
const SCENE_STAGE_EDITOR := "res://scenes/stage_editor.tscn"


## 렌더 해상도: 창(=렌더 버퍼)을 QHD(2560×1440 픽셀)로 고정. 게임 좌표는 1280×720 그대로이고
## stretch=canvas_items 라 화면은 창의 실제 픽셀 해상도로 그려진다. 모니터가 QHD 보다 작으면 16:9 로 맞춰 줄임. F11 전체 화면.
const RENDER_SIZE := Vector2i(2560, 1440)


func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if cli.has("shot"):
		win.size = RENDER_SIZE   # 스크린샷은 항상 QHD
		return
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var s := minf(1.0, minf(float(usable.size.x) / RENDER_SIZE.x, float(usable.size.y - 60) / RENDER_SIZE.y))
	var size := Vector2i(int(RENDER_SIZE.x * s), int(RENDER_SIZE.y * s))
	win.size = size
	win.position = usable.position + (usable.size - size) / 2


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		var win := get_window()
		win.mode = Window.MODE_WINDOWED if win.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


func _ready() -> void:
	call_deferred("_fit_window")
	_parse_cli()
	# 게임 기본: 밸런스 엑셀의 캐릭터·스킬·몬스터·스테이지 (읽지 못하면 코드 내장 테스트 데이터)
	data = GameData.load_from()
	if data != null:
		_balance_mtime = FileAccess.get_modified_time(GameData.BALANCE_PATH)
		allies = data.allies
		actions = data.actions
		for w in data.warnings:
			push_warning("balance.xlsx: " + w)
		set_stage(str(cli.get("stage", data.stage_order[0] if not data.stage_order.is_empty() else "")))
	else:
		push_warning("data/balance.xlsx 를 읽지 못해 내장 테스트 데이터를 씁니다")
		allies = TestRoster.build_provided_allies()
		enemies = TestRoster.build_provided_enemies()
		actions = TestRoster.build_actions()
	reset_formation()
	if cli.has("export_hud"):   # HUD 레이아웃을 scenes/battle_hud.tscn 으로 저장 (tools/export_hud_scene.gd)
		var err: int = load("res://tools/export_hud_scene.gd").run()
		get_tree().quit(0 if err == OK else 1)
		return
	if cli.has("mode"):
		mode = cli.mode
	if cli.has("preset"):
		preset = cli.preset
	if cli.has("ambush"):
		ambush = cli.ambush
	if cli.has("seed"):
		seed_value = int(cli.seed)
	if cli.has("rim"):
		rim_enabled = cli.rim != "0"
	if cli.has("scene"):
		call_deferred("_cli_jump")


func _parse_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		args = OS.get_cmdline_args()
	for a in args:
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			cli[kv[0]] = kv[1]


func _cli_jump() -> void:
	match cli.scene:
		"battle":
			start_battle()
		"formation":
			get_tree().change_scene_to_file(SCENE_FORMATION)
		"menu":
			pass
		"bench":
			get_tree().change_scene_to_file(SCENE_BENCH)
		"ai_editor":
			get_tree().change_scene_to_file(SCENE_AI_EDITOR)
		"stage_editor":
			get_tree().change_scene_to_file(SCENE_STAGE_EDITOR)
		"result":
			last_result = {"winner": cli.get("winner", "ally"), "rounds": 4, "mode": mode,
				"log": PackedStringArray(["(CLI 미리보기) 전투 로그 예시", "라운드 4 시작: 라온 → 저격수 → ...", "라온 → 지휘관: 필살기 21 피해 (전투 불능)", "전투 종료: 아군 승리"])}
			get_tree().change_scene_to_file(SCENE_RESULT)
		_:
			pass


func reset_formation() -> void:
	formation.clear()
	for u in allies:
		formation.append({"unit_id": u.id, "row": u.default_row, "index": u.default_index})


func find_ally(id: String) -> UnitData:
	return TestRoster.find_unit(allies, id)


## 컨트롤러용 로스터: 편성 반영 아군 + 기본 적군
## 스테이지 선택: 엑셀 스테이지 시트의 조명·선공·시드를 기본값으로, 적은 배치 파일에서
func set_stage(id: String) -> void:
	if data == null or not data.stages.has(id):
		return
	stage_id = id
	var st: Dictionary = data.stages[id]
	preset = st.preset
	ambush = st.ambush
	seed_value = st.seed
	enemies = data.build_stage_enemies(id)


## 실행 중 엑셀 저장 감지 (1초마다 수정 시각 확인)
func _process(delta: float) -> void:
	if data == null:
		return
	_poll_t += delta
	if _poll_t < 1.0:
		return
	_poll_t = 0.0
	var t := FileAccess.get_modified_time(GameData.BALANCE_PATH)
	if t == 0 or t == _balance_mtime:
		return
	var newer := GameData.load_from()
	if newer == null:
		return   # 저장 중이면 다음 확인 때 다시
	_balance_mtime = t
	data.apply_from(newer)
	for w in data.warnings:
		push_warning("balance.xlsx: " + w)
	print("[balance] data/balance.xlsx 다시 읽음")
	data_reloaded.emit(data.warnings)


func build_roster() -> Array:
	var out: Array = []
	if data != null and stage_id != "":
		enemies = data.build_stage_enemies(stage_id)   # 스테이지 에디터에서 바꾼 배치를 매 전투 반영
	for f in formation:
		var d := find_ally(f.unit_id)
		if d != null:
			out.append({"data": d, "row": f.row, "index": f.index})
	for e in enemies:
		out.append({"data": e, "row": e.default_row, "index": e.default_index})
	return out


func battle_scene_path() -> String:
	return SCENE_BATTLE_2D


func start_battle() -> void:
	get_tree().change_scene_to_file(battle_scene_path())


func go_menu() -> void:
	get_tree().change_scene_to_file(SCENE_MENU)


func go_formation() -> void:
	get_tree().change_scene_to_file(SCENE_FORMATION)


func show_result(result: Dictionary) -> void:
	last_result = result
	get_tree().change_scene_to_file(SCENE_RESULT)


## CLI: --shot=path [--frames=N] 가 있으면 N프레임 뒤 스크린샷 저장 후 종료.
func maybe_cli_capture(extra_wait_frames: int = 0) -> void:
	if not cli.has("shot"):
		return
	var frames := int(cli.get("frames", "20")) + extra_wait_frames
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path: String = cli.shot
	var err := img.save_png(path)
	print("[shot] saved %s (%s) err=%d" % [path, img.get_size(), err])
	if cli.get("keep", "0") != "1":
		get_tree().quit()
