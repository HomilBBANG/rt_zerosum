extends Node
## Autoload "Game": 씬 전환, 전역 설정(2D/3D 모드, 조명 프리셋, 선공, 시드, 편성), CLI 스크린샷 지원.
## 게임 루프 [임시]: 타이틀 → 새 게임/이어하기 → 기지(아웃게임) → 전투 출전 → 전투 배치(편성) → 전투 → 결과 → 기지.
## 전투 테스트 메뉴(main_menu)는 타이틀에서 따로 들어가는 개발용.

const SCENE_TITLE := "res://scenes/title.tscn"
const SCENE_BASE := "res://scenes/outgame/base_hub.tscn"
const SCENE_MENU := "res://scenes/main_menu.tscn"
const SCENE_FORMATION := "res://scenes/formation.tscn"
const SCENE_BATTLE_2D := "res://scenes/battle_2d.tscn"
const SCENE_RESULT := "res://scenes/result.tscn"
const SCENE_LOADING := "res://scenes/loading.tscn"
var loading_target := ""   # 로딩 화면이 읽을 다음 장면 (빈 칸 = 확인용 60% 정지)
var loading_kind := ""     # 로딩 멘트 장면 (기지 · 전투, 빈 칸 = 전체 멘트만)


## 로딩 화면을 거쳐 장면 바꾸기 (멘트 · 진행 바). 스크린샷(--shot) 실행은 바로 바꿈
func change_scene_loading(path: String, kind: String = "") -> void:
	if cli.has("shot") or cli.has("no_loading"):
		get_tree().change_scene_to_file(path)
		return
	loading_target = path
	loading_kind = kind
	get_tree().change_scene_to_file(SCENE_LOADING)

var _quitting := false
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
var _tree_mtime: int = 0     # data/skills.xlsx(스킬 표) + skill_tree.json + faith.json + quests.json + skill_status.json + statuses.json + monster_skills.json (에디터 '스킬 트리' 탭에서 저장하면 같이 다시 읽음)
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


## 창 크기: 창 모드 1920×1080 (게임 좌표는 1280×720 그대로, stretch=canvas_items 라 창의 실제 픽셀 해상도로 그려짐).
## 화면(작업 표시줄 · 제목줄 제외)보다 크면 16:9 로 맞춰 줄임. F11 = 전체 화면. 스크린샷(--shot)은 QHD 2560×1440 고정.
const WINDOW_SIZE := Vector2i(1920, 1080)
const RENDER_SIZE := Vector2i(2560, 1440)


func _fit_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var win := get_window()
	if cli.has("shot"):
		win.size = RENDER_SIZE   # 스크린샷은 항상 QHD (--win=가로x세로 = 다른 창 크기 · 비율 확인용)
		if cli.has("win"):
			var wh := str(cli.win).split("x")
			win.size = Vector2i(int(wh[0]), int(wh[1]))
		return
	if Engine.is_embedded_in_editor():
		return   # 에디터 '게임' 탭 안에 넣어 실행하면 크기는 에디터가 정함
	if win.mode != Window.MODE_WINDOWED:
		win.mode = Window.MODE_WINDOWED   # 최대화 · 전체 화면으로 시작해도 창 모드로 (F11 로 전체 화면)
	# 창 제목줄 · 테두리까지 화면(작업 표시줄 제외)에 들어가게: 실제 장식 크기를 재서 그만큼 빼고, 장식 포함 사각형을 가운데로.
	# (예전엔 제목줄을 60px 로 어림하고 안쪽만 가운데 맞춤 → 화면 배율이 큰 모니터에서 아래가 작업 표시줄 뒤로 잘림)
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	win.size = Vector2i(640, 360)
	await get_tree().process_frame
	var deco := win.get_size_with_decorations() - win.size
	var off := win.position - win.get_position_with_decorations()   # 장식 왼쪽 위 → 안쪽 왼쪽 위
	if deco.y <= 0:   # 장식 크기를 못 재면 넉넉히 어림 (제목줄 + 테두리)
		deco = Vector2i(16, 80)
		off = Vector2i(8, 72)
	var room := usable.size - deco - Vector2i(8, 8)
	var want: Vector2i = Settings.win_size if Settings.win_size.x >= 640 else WINDOW_SIZE   # 설정 '창 크기' (없으면 1920×1080)
	var s := minf(1.0, minf(float(room.x) / want.x, float(room.y) / want.y))
	var size := Vector2i(int(want.x * s), int(want.y * s))
	win.size = size
	win.position = usable.position + (usable.size - (size + deco)) / 2 + off
	_restore_window_rect(win, deco, off)
	if Settings.fullscreen:
		win.mode = Window.MODE_FULLSCREEN


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F11:
		set_fullscreen(get_window().mode != Window.MODE_FULLSCREEN)


## 마지막으로 끈 창 위치 · 크기로 (그 사각형이 어떤 화면 안에 다 들어갈 때만 — 모니터를 바꿨으면 가운데 그대로)
func _restore_window_rect(win: Window, deco: Vector2i, off: Vector2i) -> void:
	var sz := Settings.win_last
	var pos := Settings.win_pos
	if sz.x < 640 or sz.y < 360 or pos.x < -90000:
		return
	var outer := Rect2i(pos - off, sz + deco)   # 제목줄 · 테두리 포함
	for i in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(i).encloses(outer):
			win.size = sz
			win.position = pos
			return


## 지금 창 위치 · 크기를 설정에 적어 둠 (창 모드일 때만 — 게임을 끌 때)
func remember_window() -> void:
	if DisplayServer.get_name() == "headless" or cli.has("shot") or Engine.is_embedded_in_editor():
		return
	var win := get_window()
	if win.mode != Window.MODE_WINDOWED:
		return
	Settings.win_last = win.size
	Settings.win_pos = win.position
	Settings.save_all()


## 전체 화면 켜고 끄기 (설정에 저장)
func set_fullscreen(on: bool) -> void:
	var win := get_window()
	win.mode = Window.MODE_FULLSCREEN if on else Window.MODE_WINDOWED
	Settings.fullscreen = on
	Settings.save_all()


## 창 모드 크기 바꾸기 (설정 '창 크기'): 화면(작업 표시줄 · 제목줄 제외)에 안 들어가면 비율 유지하며 줄이고 가운데로
func set_window_size(want: Vector2i) -> void:
	var win := get_window()
	if Engine.is_embedded_in_editor():
		return
	win.mode = Window.MODE_WINDOWED
	Settings.fullscreen = false
	var usable := DisplayServer.screen_get_usable_rect(win.current_screen)
	var deco := win.get_size_with_decorations() - win.size
	var off := win.position - win.get_position_with_decorations()
	if deco.y <= 0:
		deco = Vector2i(16, 80)
		off = Vector2i(8, 72)
	var room := usable.size - deco - Vector2i(8, 8)
	var s := minf(1.0, minf(float(room.x) / want.x, float(room.y) / want.y))
	var size := Vector2i(int(want.x * s), int(want.y * s))
	win.size = size
	win.position = usable.position + (usable.size - (size + deco)) / 2 + off
	Settings.win_size = want
	Settings.win_last = size
	Settings.win_pos = win.position
	Settings.save_all()


## 끝날 때 static 캐시(캐릭터 그림 · 발자국 소리)를 비움 — 안 비우면 종료 때 "ObjectDB instances were leaked" · "resources still in use" 경고
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:   # 창 닫기 버튼도 quit_game 으로 (auto_accept_quit 끔)
		quit_game()


func _exit_tree() -> void:
	Sfx.shutdown(get_tree())
	CharacterSprite2D.clear_cache()


## 게임 끝내기: 소리를 먼저 멈추고 오디오가 한 번 돈 뒤 끝냄 (재생 중에 끝내면 소리 객체가 남았다는 경고)
func quit_game() -> void:
	if _quitting:
		return
	_quitting = true
	remember_window()   # 다음 실행 때 같은 자리 · 크기로
	Sfx.shutdown(get_tree())
	CharacterSprite2D.clear_cache()
	for i in 3:
		await get_tree().process_frame
	get_tree().quit()


func _ready() -> void:
	get_tree().auto_accept_quit = false
	Settings.load_all()   # 음량 · 창 크기 · 전체 화면 (user://settings.cfg)
	call_deferred("_fit_window")
	_parse_cli()
	# 게임 기본: 밸런스 엑셀의 캐릭터·스킬·몬스터·스테이지 (읽지 못하면 코드 내장 테스트 데이터)
	data = GameData.load_from()
	if data != null:
		_balance_mtime = FileAccess.get_modified_time(GameData.BALANCE_PATH)
		_tree_mtime = FileAccess.get_modified_time(SkillTreeData.PATH) + FileAccess.get_modified_time(FaithData.PATH) + FileAccess.get_modified_time(QuestData.PATH) + FileAccess.get_modified_time(CutsceneData.PATH) + FileAccess.get_modified_time(SkillStatusData.PATH) + FileAccess.get_modified_time(MonsterSkillData.PATH) + FileAccess.get_modified_time(StatusCatalog.PATH) + SkillTable.mtime()
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
						if bool(sk.get("divine", false)):   # 기적 탭 테스트: 정체 해금 + 의지 올려 둠
							cli["base_ui"] = "divine:%s:%d;faith:%s" % [sk.get("char", ""), int(sk.get("will", 0)), sk.get("char", "")]
				if req.get("cutscene") is String:   # 컷씬 탭: 새 기지에서 그 컷씬을 그 컷부터 재생
					cli["editor_base"] = true
					cli["base_ui"] = "cutscene:%s:%d" % [req.cutscene, int(req.get("step", 0))]
				if req.get("quest") is String:   # 퀘스트 탭: 새 기지에서 그 퀘스트를 시작(필요하면 단계 건너뛰기)하고 퀘스트 창
					cli["editor_base"] = true
					cli["base_ui"] = "quest:%s:%d" % [req.quest, int(req.get("step", 0))]
				if str(req.get("try_skill", "")) != "":   # 스킬 트리 탭 '상태 이상': 그 스킬을 아군 모두의 첫 스킬 칸에
					cli["try_skill"] = str(req.try_skill)
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
		"loading":   # 로딩 화면 확인용 (60% 에 멈춤, --loading_kind=기지|전투)
			loading_target = ""
			loading_kind = str(cli.get("loading_kind", ""))
			get_tree().change_scene_to_file(SCENE_LOADING)
		"base":
			start_base_session(cli.get("new", "1") == "1")
			go_base()
		"result":   # 결과 화면 미리보기 (--winner=ally|enemy). 새 기지에 전투 결과를 반영해 경험치 · 전리품까지 보이게
			var demo := [[18, 2, 1.0, true, []], [42, 3, 0.55, true, ["bleed", "slow"]], [25, 1, 0.8, true, ["burn"]], [8, 0, 0.0, false, ["bleed", "blind", "vulnerable"]], [12, 1, 1.0, true, []], [5, 0, 0.3, true, ["stun"]]]
			var al := []
			var fm: Array = formation.map(func(e): return str(e.unit_id))
			var picks: Array = allies.filter(func(u): return fm.is_empty() or fm.has(u.id)).slice(0, 4)
			for i in picks.size():
				var u: UnitData = picks[i]
				var d: Array = demo[i % demo.size()]
				al.append({"id": u.id, "hp": int(u.max_hp * float(d[2])), "max_hp": u.max_hp, "alive": d[3], "statuses": d[4], "dmg": d[0], "kills": d[1]})
			last_result = {"winner": cli.get("winner", "ally"), "rounds": 5, "mode": mode, "stage": stage_id, "enemies_total": 4, "enemies_down": 2,
				"log": PackedStringArray(["(CLI 미리보기) 전투 로그 예시", "라운드 4 시작", "전투 종료: 아군 승리"]), "allies": al}
			if start_base_session(true):
				base.apply_battle_result(last_result)
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
	var tt := FileAccess.get_modified_time(SkillTreeData.PATH) + FileAccess.get_modified_time(FaithData.PATH) + FileAccess.get_modified_time(QuestData.PATH) + FileAccess.get_modified_time(CutsceneData.PATH) + FileAccess.get_modified_time(SkillStatusData.PATH) + FileAccess.get_modified_time(MonsterSkillData.PATH) + FileAccess.get_modified_time(StatusCatalog.PATH) + SkillTable.mtime()
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
	print("[balance] data/balance.xlsx · skills.xlsx · skill_tree.json · faith.json · quests.json · cutscenes.json · skill_status.json · statuses.json · monster_skills.json 다시 읽음")
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
## 저장 칸 3개 (user://save_1.json ~ save_3.json). 지금 칸 = save_slot (새 게임 · 불러오기에서 정함, 자동 저장도 이 칸에)
## 예전 저장(user://outgame_save.json)은 처음 한 번 1번 칸으로 옮김.
const SAVE_SLOTS := 3
var save_slot := 1
signal saved(slot: int)   # 저장할 때마다 (기지 HUD 의 자동 저장 표시)


func slot_path(i: int) -> String:
	return "user://save_%d.json" % i


func _migrate_old_save() -> void:
	if FileAccess.file_exists(SAVE_PATH) and not FileAccess.file_exists(slot_path(1)):
		DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(slot_path(1)))


func has_slot(i: int) -> bool:
	_migrate_old_save()
	return FileAccess.file_exists(slot_path(i))


## 저장이 하나라도 있나 (타이틀 '이어하기')
func has_save() -> bool:
	for i in range(1, SAVE_SLOTS + 1):
		if has_slot(i):
			return true
	return false


## 가장 최근에 저장한 칸 (없으면 0)
func latest_slot() -> int:
	var best := 0
	var best_t := -1
	for i in range(1, SAVE_SLOTS + 1):
		if has_slot(i):
			var t := FileAccess.get_modified_time(slot_path(i))
			if t > best_t:
				best_t = t
				best = i
	return best


## 칸 정보 {exists, label(게임 날짜), cash, saved_at(실제 저장 시각)} — 타이틀 저장 칸 창
func slot_info(i: int) -> Dictionary:
	if not has_slot(i):
		return {"exists": false}
	var out := {"exists": true, "label": "", "cash": -1, "saved_at": Time.get_datetime_string_from_unix_time(FileAccess.get_modified_time(slot_path(i)) + _tz_bias(), true)}
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(i)))
	if j is Dictionary and j.get("meta") is Dictionary:
		out.label = str(j.meta.get("label", ""))
		out.cash = int(j.meta.get("cash", -1))
	return out


func _tz_bias() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## 기지 세션 준비: new_game = true 면 새로 시작, 아니면 지금 칸(save_slot) 불러오기 (없으면 새로)
func start_base_session(new_game: bool = true) -> bool:
	if outgame_data == null:
		return false
	autosave = not cli.has("editor_base") and not cli.has("shot")
	if not new_game and has_slot(save_slot):
		var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(save_slot)))
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
	var f := FileAccess.open(slot_path(save_slot), FileAccess.WRITE)
	if f == null:
		return false
	var d := base.to_dict()
	d["formation"] = formation
	d["stage_id"] = stage_id
	d["meta"] = {"label": base.clock.label(), "cash": base.ledger.cash}   # 저장 칸 창에 보일 요약
	f.store_string(JSON.stringify(d))
	f.close()
	saved.emit(save_slot)
	return true


## 칸 i 를 불러와 그 칸으로 이어하기 (i = 0 이면 가장 최근 칸)
func load_campaign(i: int = 0) -> bool:
	save_slot = i if i > 0 else maxi(1, latest_slot())
	if not start_base_session(false):
		return false
	var j: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_path(save_slot)))
	if j is Dictionary:
		if j.get("formation") is Array and not (j.formation as Array).is_empty():
			formation = []
			for e in j.formation:
				formation.append({"unit_id": str(e.unit_id), "row": int(e.row), "index": int(e.index)})
		if str(j.get("stage_id", "")) != "":
			set_stage(str(j.stage_id))
	return true


func delete_save() -> void:
	if has_slot(save_slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(save_slot)))


func go_title() -> void:
	campaign = false
	change_scene_loading(SCENE_TITLE)


func go_base() -> void:
	campaign = true
	change_scene_loading(SCENE_BASE, "기지")


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
	change_scene_loading(battle_scene_path(), "전투")


## 전투·편성·결과의 "메뉴/돌아가기": 기지에서 출전했으면 기지로, 아니면 전투 테스트 메뉴로
func go_menu() -> void:
	if campaign and base != null:
		go_base()
	else:
		get_tree().change_scene_to_file(SCENE_MENU)


func go_formation() -> void:
	change_scene_loading(SCENE_FORMATION, "전투")


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
		quit_game()
