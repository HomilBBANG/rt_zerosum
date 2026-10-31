extends Control
## 로딩 화면 (레퍼런스 art_src/ui/loading/ref_loading.png): 검은 바탕 · 가운데 로딩 멘트 · 진행 바(그림 bar_frame + 크림색 채움 + %) ·
## 돌아가는 점선 고리 + "로딩 중..." · 맨 아래 작은 ZEROSUM 로고.
## Game.change_scene_loading(경로, 장면) 이 이 화면으로 바꾸면, 다음 장면을 백그라운드로 읽으며 진행률을 보여 주고 다 읽으면 넘어감.
## 멘트 = data/loading_tips.xlsx (LoadingTips — 엑셀에서 직접 추가 · 수정, 장면별로 고름). 멘트를 읽을 수 있게 최소 MIN_TIME 초는 보임.
## 진행 = 파일 읽기 0~85% → 장면 준비(새 장면을 이 화면 아래에 붙여 _ready — 기지 3D 건물 만들기 등 — 를 끝냄) 85~100% → 넘어감.
## 그래서 넘어간 직후 멈칫하지 않음. 화면은 CanvasLayer 100 에 그려 새 장면(HUD 포함)보다 위.

const MIN_TIME := 1.2
const K := 1280.0 / 1672.0                      # 레퍼런스 그림 → 게임 좌표
const BAR_POS := Vector2(420, 479) * K          # 바 그림 왼쪽 위
const BAR_SIZE := Vector2(833, 66) * K
const FILL := Rect2(Vector2(39, 18) * K, Vector2(756, 28) * K)   # 바 안쪽 (채움 칸)
const CREAM := Color(0.89, 0.83, 0.68)

var target := ""
var scene_kind := ""
var _t := 0.0
var _shown := 0.0
var _real := 0.0
var _done := false
var _demo := false        # 읽을 장면 없음 (--scene=loading 확인용): 60% 에 멈춤
var _tip: Label
var _pct: Label
var _font: Font
var _bold: Font
var _frame: Texture2D
var _logo: Texture2D
var _ui: Control          # 로딩 화면 그림 (맨 위 CanvasLayer)
var _setting_up := false  # 장면 준비 단계 (85% 이후)
const READ_PART := 0.85   # 파일 읽기가 차지하는 진행 비율


func _ready() -> void:
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	_frame = load("res://assets/ui/loading/bar_frame.png")
	_logo = load("res://assets/ui/title/logo.png")
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = 100   # 준비 중인 새 장면(HUD 층 포함)보다 위
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_ui.mouse_filter = MOUSE_FILTER_STOP
	_ui.draw.connect(_draw_ui)
	layer.add_child(_ui)
	target = Game.loading_target
	scene_kind = Game.loading_kind
	_demo = target == ""
	# 로딩 멘트 (바 위, 레퍼런스의 어두운 칸 자리)
	_tip = Label.new()
	_tip.text = LoadingTips.pick(scene_kind)
	_tip.add_theme_font_override("font", _font)
	_tip.add_theme_font_size_override("font_size", 19)
	_tip.add_theme_color_override("font_color", CREAM)
	_tip.add_theme_constant_override("line_spacing", 6)
	_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip.position = Vector2(390, 262)   # 바 바로 위 (레퍼런스보다 조금 아래)
	_tip.size = Vector2(500, 94)
	_ui.add_child(_tip)
	_pct = Label.new()
	_pct.add_theme_font_override("font", _bold)
	_pct.add_theme_font_size_override("font_size", 13)
	_pct.add_theme_color_override("font_color", CREAM)
	_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pct.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_pct.position = BAR_POS + FILL.position
	_pct.size = Vector2(FILL.size.x - 8, FILL.size.y)
	_ui.add_child(_pct)
	if _demo:
		_shown = 0.6
	elif ResourceLoader.load_threaded_request(target) != OK:
		_demo = false
		_finish_sync()
	if Game.cli.get("scene", "") == "loading":
		Game.maybe_cli_capture()


func _process(delta: float) -> void:
	_t += delta
	if not _demo and not _done and not _setting_up:
		var prog := []
		var st := ResourceLoader.load_threaded_get_status(target, prog)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_real = 1.0
		elif st == ResourceLoader.THREAD_LOAD_IN_PROGRESS and not prog.is_empty():
			_real = float(prog[0])
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_finish_sync()
			return
		# 보이는 진행률 = 실제 진행률과 시간 진행률(MIN_TIME) 중 느린 쪽으로 부드럽게 (파일 읽기 = 0~85%)
		var want := minf(_real, _t / MIN_TIME) * READ_PART
		_shown = move_toward(_shown, want, delta * 2.5)
		if _real >= 1.0 and _shown >= READ_PART - 0.001 and not _setting_up:
			_setting_up = true
			_setup_scene.call_deferred(ResourceLoader.load_threaded_get(target))
	if not _setting_up:
		_pct.text = "%d%%" % roundi(_shown * 100.0)
	_ui.queue_redraw()


## 장면 준비: 새 장면을 로딩 화면 아래에 붙여 _ready(무거운 준비)를 끝내고, 몇 프레임 뒤 85 → 100% 채우고 넘어감
func _setup_scene(ps: PackedScene) -> void:
	if ps == null:
		_finish_sync()
		return
	_pct.text = "%d%%" % roundi(_shown * 100.0)
	await RenderingServer.frame_post_draw   # 85% 화면을 먼저 보여 주고
	var inst := ps.instantiate()
	get_tree().root.add_child(inst)         # 여기서 새 장면 _ready (기지 = 3D 건물 · 대원 만들기)
	for i in 3:                             # 미뤄 둔 준비(call_deferred · 첫 그림자 렌더)까지
		await get_tree().process_frame
	while _shown < 0.999:
		_shown = move_toward(_shown, 1.0, get_process_delta_time() * 3.0)
		_pct.text = "%d%%" % roundi(_shown * 100.0)
		_ui.queue_redraw()
		await get_tree().process_frame
	_done = true
	get_tree().current_scene = inst
	queue_free()


func _finish_sync() -> void:
	_done = true
	get_tree().change_scene_to_file.call_deferred(target)


func _draw_ui() -> void:
	_ui.draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color(0.0, 0.0, 0.0))
	# 멘트 칸 (레퍼런스의 아주 어두운 판)
	var tb := Rect2(_tip.position, _tip.size).grow_individual(24, 0, 24, 0)
	_ui.draw_rect(tb, Color(0.035, 0.038, 0.032))
	_ui.draw_rect(tb, Color(0.06, 0.065, 0.055), false, 1.0)
	# 진행 바: 그림 틀 + 크림색 채움
	_ui.draw_texture_rect(_frame, Rect2(BAR_POS, BAR_SIZE), false)
	var f := Rect2(BAR_POS + FILL.position, Vector2(FILL.size.x * clampf(_shown, 0.0, 1.0), FILL.size.y))
	if f.size.x > 0.5:
		_ui.draw_rect(f, CREAM)
		_ui.draw_rect(Rect2(f.position, Vector2(f.size.x, 1.5)), Color(0.96, 0.92, 0.80))   # 위 밝은 줄
	# 돌아가는 점선 고리 + "로딩 중..."
	var c := Vector2(583, 453)
	var n := 12
	var head := int(_t * 12.0) % n
	for i in n:
		var a := TAU * float(i) / n
		var age := (head - i + n) % n
		var col := CREAM.lerp(Color(0.32, 0.30, 0.24), clampf(age / float(n - 1), 0.0, 1.0))
		var dir := Vector2(cos(a), sin(a))
		_ui.draw_line(c + dir * 12.0, c + dir * 19.0, col, 4.0, true)
	var dots := ".".repeat(1 + int(_t * 2.0) % 3)
	_ui.draw_string(_bold, Vector2(624, 461), "로딩 중" + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, CREAM)
	# 맨 아래 로고
	if _logo != null:
		var lw := 138.0
		var lh := lw * _logo.get_height() / float(_logo.get_width())
		_ui.draw_texture_rect(_logo, Rect2(645 - lw * 0.5, 679 - lh * 0.5, lw, lh), false)
