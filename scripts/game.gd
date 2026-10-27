extends Node
## Autoload "Game": 씬 전환, 전역 설정(2D/3D 모드, 조명 프리셋, 선공, 시드, 편성), CLI 스크린샷 지원.
## 게임 루프 [임시]: 타이틀 → 게임 시작/이어하기 → 기지(아웃게임) → 전투 출전 → 전투 배치(편성) → 전투 → 결과 → 기지.
## 전투 테스트 메뉴(main_menu)는 타이틀에서 따로 들어가는 개발용.

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_BASE := "res://scenes/outgame/base_hub.tscn"
const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_FORMATION := "res://scenes/formation.tscn"
const SCENE_BATTLE_2D := "res://scenes/battle_2d.tscn"
const SCENE_RESULT := "res://scenes/result.tscn"

var mode: String = "2d"            # 캐릭터 2D + 3D 배경 하나뿐 (3D 전투 씬 2026-10-27 제거). 결과 기록용 이름만 남김
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
var _tree_mtime: int = 0     # data/skill_tree.json + data/faith.json (에디터 '스킬 트리' 탭에서 저장하면 같이 다시 읽음)
var _poll_t: float = 0.0
## 아웃게임 (data/outgame.xlsx + 대원 일정). base = 진행 중인 기지 (없으면 null)
const SAVE_PATH := "user://outgame_save.json"
var outgame_data: OutgameData = null
var base: BaseSim = null
var campaign: bool = false          # 기지에서 출전한 전투인가 (결과 → 기지로)
var autosave: bool = true           # 에디터 테스트 플레이는 저장하지 않음
signal outgame_reloaded(warnings: PackedStringArray)
var _outgame_mtime: int = 0
var _sched_mtime: int = 0
var _ally_copies: Array = []        # [{copy, base}] 기지 성장(훈련·장비)을 반영한 전투용 아군 복제본


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
		_tree_mtime = FileAccess.get_modified_time(SkillTreeData.PATH) + FileAccess.get_modified_time(FaithData.PATH)
		allies = data.allies
		actions = data.actions
		for w in data.warnings:
			push_warning("balance.xlsx: " + w)
		set_stage(str(cli.get("stage", data.stage_order[0] if not data.stage_order.is_empty() else "")))
		# Godot 에디터 스테이지 탭에서 "테스트 플레이" 로 실행했으면 그 스테이지
		if FileAccess.file_exists(GameData.EDITOR_PLAY_PATH):
			var req: Variant = JSON.parse_string(FileAccess.get_file_as_string(GameData.EDITOR_PLAY_PATH))
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GameData.EDITOR_PLAY_PATH))
			if req is Dictionary:
				set_stage(str(req.get("stage", stage_id)))
				if req.get("base", false):   # 일정 탭 "기지 테스트 플레이": 새 기지, 저장 안 함, 카메라는 그 대원
					cli["editor_base"] = true
					cli["base_focus"] = str(req.get("npc", ""))
					if req.get("battle_soon", false):   # 전투 발생 탭: 다음 전투 10분 전부터
						cli["base_battle_soon"] = true
					if req.get("skills") is Dictionary:   # 스킬 트리 탭: 기지에서 그 대원 스킬 창 (레벨 올린 상태)
						var sk: Dictionary = req.skills
						cli["base_ui"] = "skills:%s:L%d:::%s" % [sk.get("char", ""), int(sk.get("level", 1)), sk.get("kind", "active")]
				if req.get("sortie", false):   # 출정 대사 탭: 새 기지에서 출정 대기 화면 (대원 상태 섞기)
					cli["editor_base"] = true
					cli["scene"] = "sortie"
					if req.get("demo", false):
						cli["sortie_demo"] = "1"
	else:
		push_warning("data/balance.xlsx 를 읽지 못해 내장 테스트 데이터를 씁니다")
		allies = TestRoster.build_provided_allies()
		enemies = TestRoster.build_provided_enemies()
		actions = TestRoster.build_actions()
	_apply_test_char()
	reset_formation()
	outgame_data = OutgameData.load_from()
	_apply_test_char()
	if outgame_data != null:
		_outgame_mtime = FileAccess.get_modified_time(OutgameData.PATH)
		_sched_mtime = outgame_data.schedules_mtime()
		for w in outgame_data.warnings:
			push_warning("outgame.xlsx: " + w)
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


## 테스트 캐릭터 그림: --test_char=<assets/characters 폴더> [--test_slot=a_nikita] — 그 아군(전투)과 같은 인물(기지)의 그림만 바꿔서 렌더 확인
func _apply_test_char() -> void:
	if cli.has("char_style"):
		CharacterSprite2D.style_override["style"] = str(cli.char_style)
	if cli.has("char_gradient"):
		CharacterSprite2D.style_override["neon_gradient"] = float(cli.char_gradient)
	var cid := str(cli.get("test_char", ""))
	if cid == "":
		return
	var slot := str(cli.get("test_slot", "a_nikita"))
	for u in allies:
		if u.id == slot:
			u.sprite_id = cid
			u.palette["sprite_id"] = cid
			u.palette.erase("eye_paint")   # 새 그림 눈 색 그대로
	if outgame_data != null:
		for nid in outgame_data.npcs:
			if outgame_data.npcs[nid].character_id == slot:
				outgame_data.npcs[nid].sprite = cid


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
		"sortie":   # 새 기지에서 출전한 것처럼 출정 대기 화면 (--sortie_demo=1: 대원 상태를 섞어서 말풍선 확인)
			start_base_session(true)
			if cli.get("sortie_demo", "0") == "1":
				_sortie_demo()
			sortie(stage_id)
		"menu":
			go_menu_test()
		"title":
			pass
		"base":
			start_base_session(cli.get("new", "1") == "1")
			go_base()
		"result":
			last_result = {"winner": cli.get("winner", "ally"), "rounds": 4, "mode": mode,
				"log": PackedStringArray(["(CLI 미리보기) 전투 로그 예시", "라운드 4 시작: 라온 → 저격수 → ...", "라온 → 지휘관: 필살기 21 피해 (전투 불능)", "전투 종료: 아군 승리"])}
			get_tree().change_scene_to_file(SCENE_RESULT)
		_:
			pass


## CLI·에디터 테스트용: 대원 상태를 여러 가지로 (피로·부상·친밀도·외부 의뢰)
func _sortie_demo() -> void:
	if base == null:
		return
	var set_cs := func(uid: String, d: Dictionary):
		var cs := base.cstate_of(uid)
		for k in d:
			cs[k] = d[k]
	set_cs.call("a_kira", {"fatigue": 85.0})
	set_cs.call("a_dan", {"statuses": ["injured"], "hp": float(base.char_max_hp("a_dan")) * 0.3})
	set_cs.call("a_nikita", {"affinity": 82.0})
	set_cs.call("a_hana", {"affinity": 76.0, "fatigue": 10.0})
	for nid in base.npcs:
		if base.npcs[nid].character_id == "a_ethan":
			base.npcs[nid].state = NpcAgent.UNAVAILABLE


func reset_formation() -> void:
	formation.clear()
	for u in allies:
		formation.append({"unit_id": u.id, "row": u.default_row, "index": u.default_index})


## 출정 대기: 이 대원이 못 나가는 이유 ("" = 출정 가능). 기지에서 외부 의뢰로 나가 있으면 출정 불가
func sortie_block_reason(uid: String) -> String:
	if not (campaign and base != null):
		return ""
	for nid in base.npcs:
		var n: NpcAgent = base.npcs[nid]
		if n.character_id == uid and n.state == NpcAgent.UNAVAILABLE:
			return "외부 의뢰 중"
	return ""


## 출정 못 하는 대원을 편성에서 뺌
func prune_formation() -> void:
	formation = formation.filter(func(f): return find_ally(str(f.unit_id)) != null and sortie_block_reason(str(f.unit_id)) == "")


## 출정 대기 화면 표시·대사 조건용 몸 상태 {affinity, fatigue, hp, max_hp, statuses, known}
## 기지에서 출전하지 않은 전투(테스트 메뉴)는 기지 상태가 없으므로 known = false (친밀도 50 · 피로 0 · 체력 가득)
func sortie_state(uid: String) -> Dictionary:
	if campaign and base != null:
		var cs := base.cstate_of(uid)
		return {"affinity": float(cs.affinity), "fatigue": float(cs.fatigue), "hp": float(cs.hp), "max_hp": float(base.char_max_hp(uid)),
			"statuses": (cs.statuses as Array).duplicate(), "known": true}
	var u := find_ally(uid)
	var mh := float(u.max_hp) if u != null else 100.0
	return {"affinity": 50.0, "fatigue": 0.0, "hp": mh, "max_hp": mh, "statuses": [], "known": false}


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
	_poll_t += delta
	if _poll_t < 1.0:
		return
	_poll_t = 0.0
	_poll_outgame()
	if data == null:
		return
	var t := FileAccess.get_modified_time(GameData.BALANCE_PATH)
	var tt := FileAccess.get_modified_time(SkillTreeData.PATH) + FileAccess.get_modified_time(FaithData.PATH)
	if t == 0 or (t == _balance_mtime and tt == _tree_mtime):
		return
	var newer := GameData.load_from()
	if newer == null:
		return   # 저장 중이면 다음 확인 때 다시
	_balance_mtime = t
	_tree_mtime = tt
	data.apply_from(newer)
	for w in data.warnings:
		push_warning("balance.xlsx: " + w)
	for e in _ally_copies:
		_derive_ally(e.copy, e.base)
	print("[balance] data/balance.xlsx · skill_tree.json · faith.json 다시 읽음")
	data_reloaded.emit(data.warnings)


## 기지 엑셀·대원 일정 파일이 바뀌면 다시 읽어 진행 중인 기지에 반영
func _poll_outgame() -> void:
	if outgame_data == null:
		return
	var t := FileAccess.get_modified_time(OutgameData.PATH)
	var ts := outgame_data.schedules_mtime()
	if (t == 0 or t == _outgame_mtime) and ts == _sched_mtime:
		return
	var newer := OutgameData.load_from()
	if newer == null:
		return
	_outgame_mtime = t
	_sched_mtime = ts
	outgame_data = newer
	if base != null:
		base.set_data(newer)
	for w in newer.warnings:
		push_warning("outgame.xlsx: " + w)
	print("[outgame] 기지 데이터 다시 읽음")
	outgame_reloaded.emit(newer.warnings)


func build_roster() -> Array:
	var out: Array = []
	if data != null and stage_id != "":
		enemies = data.build_stage_enemies(stage_id)   # 스테이지 에디터에서 바꾼 배치를 매 전투 반영
	_ally_copies.clear()
	for f in formation:
		var d := find_ally(f.unit_id)
		if d != null:
			var entry := {"row": f.row, "index": f.index}
			if campaign and base != null:   # 기지 훈련·장비·강화 + 남은 체력·상태 이상 반영 (전투 규칙은 그대로, 수치만)
				var c := UnitData.new()
				_derive_ally(c, d)
				_ally_copies.append({"copy": c, "base": d})
				entry.merge(base.battle_entry(d.id))
				d = c
			entry["data"] = d
			out.append(entry)
	for e in enemies:
		out.append({"data": e, "row": e.default_row, "index": e.default_index})
	return out


func _derive_ally(copy: UnitData, src: UnitData) -> void:
	GameData._copy_props(copy, src)
	if base != null:
		base.apply_to_ally(copy, src)


## 편성 화면 표시용: 기지 성장이 반영된 아군 (캠페인이 아니면 원본)
func ally_view(u: UnitData) -> UnitData:
	if not (campaign and base != null):
		return u
	var c := UnitData.new()
	_derive_ally(c, u)
	return c


# ---------------------------------------------------------------- 아웃게임 (기지)
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## 기지 세션 준비: new_game = true 면 새로 시작, 아니면 저장 불러오기 (없으면 새로)
func start_base_session(new_game: bool = true) -> bool:
	if outgame_data == null:
		return false
	autosave = not cli.has("editor_base") and not cli.has("shot")
	if not new_game and has_save():
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if j is Dictionary:
			base = BaseSim.from_dict(outgame_data, data, j)
			campaign = true
			return true
	base = BaseSim.create(outgame_data, data)
	campaign = true
	if new_game:
		reset_formation()
	save_campaign()
	return true


func save_campaign() -> bool:
	if base == null or not autosave:
		return base != null
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var d := base.to_dict()
	d["formation"] = formation
	d["stage_id"] = stage_id
	f.store_string(JSON.stringify(d))
	return true


func load_campaign() -> bool:
	if not start_base_session(false):
		return false
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if j is Dictionary:
		if j.get("formation") is Array and not (j.formation as Array).is_empty():
			formation = []
			for e in j.formation:
				formation.append({"unit_id": str(e.unit_id), "row": int(e.row), "index": int(e.index)})
		if str(j.get("stage_id", "")) != "":
			set_stage(str(j.stage_id))
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func go_title() -> void:
	campaign = false
	get_tree().change_scene_to_file(SCENE_TITLE)


func go_base() -> void:
	campaign = true
	get_tree().change_scene_to_file(SCENE_BASE)


## 기지 → 전투 출전 → 전투 배치(편성)
func sortie(p_stage: String) -> void:
	set_stage(p_stage)
	campaign = true
	restart_count = 0
	save_campaign()
	go_formation()


func go_menu_test() -> void:
	campaign = false
	get_tree().change_scene_to_file(SCENE_MENU)


func battle_scene_path() -> String:
	return SCENE_BATTLE_2D


func start_battle() -> void:
	get_tree().change_scene_to_file(battle_scene_path())


## 전투·편성·결과의 "메뉴/돌아가기": 기지에서 출전했으면 기지로, 아니면 전투 테스트 메뉴로
func go_menu() -> void:
	if campaign and base != null:
		go_base()
	else:
		get_tree().change_scene_to_file(SCENE_MENU)


func go_formation() -> void:
	get_tree().change_scene_to_file(SCENE_FORMATION)


func show_result(result: Dictionary) -> void:
	last_result = result
	if campaign and base != null:   # 잃은 체력·상태 이상·피로를 기지로 (체력은 의무실에서만 회복)
		base.apply_battle_result(result)
		save_campaign()
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
