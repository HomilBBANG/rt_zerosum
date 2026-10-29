@tool
class_name CutscenePlayer
extends Control
## 컷씬 재생 화면 (data/cutscenes.json — CutsceneData). 기지 HUD 와 에디터 '컷씬' 탭 미리보기가 같이 씀.
## 1280x720 무대(stage)를 그린 뒤 크기에 맞춰 줄임 → 에디터 작은 창에서도 게임과 같은 배치.
## 대사: 말하는 대원이 왼쪽/오른쪽에 서고(말하는 쪽 밝게, 다른 쪽 어둡게) 아래 상자에 이름·글(한 글자씩).
## CG: 화면 전체 그림 — 'CG 끄기'(그림 없는 CG 컷)나 배경 컷이 나올 때까지 대사·나레이션이 그 위에 나옴 (그동안 서 있는 대원은 숨김).
## 진행: 클릭 · Space · Enter = 다음 (글이 나오는 중이면 다 보이기) · Esc / '건너뛰기' = 끝까지 (행동 컷은 그대로 적용, 선택지는 '끝' 을 고른 것으로).
## 선택지: 고른 것의 next 컷씬으로 이어짐 ("" = 이 컷씬 다음 컷으로). 컷씬이 끝나면 next 컷씬으로 이어짐.

signal cutscene_started(id: String)        # 이어진 컷씬마다 (BaseSim 이 '본 컷씬' 으로 기록)
signal action_requested(step: Dictionary)  # 행동 컷 (퀘스트 시작 · 신 정체 해금 · 친밀도 · 현금)
signal finished(last_id: String)

const STAGE := Vector2(1280, 720)
const CPS := 48.0                          # 글자 / 초
const DIM := Color(0.6, 0.6, 0.66)

var defs: Dictionary = {}                  # 컷씬 id → 컷씬
var npcs: Dictionary = {}                  # OutgameData.npcs (이름 · 그림)
var keys := true                           # 키보드로 진행 (에디터 미리보기는 끔)
var dim_alpha := 0.75                      # 배경 그림이 없을 때 뒤(기지 화면)를 덮는 정도

var cur: Dictionary = {}
var idx := -1
var playing := false
var slots := {"left": "", "right": ""}     # 서 있는 대원 id
var poses := {"left": "", "right": ""}     # 서 있는 대원 포즈 ("" = 기본 그림)
var _shown := 0.0
var _typing := false
var _waiting_choice := false
var _visited := {}
var _tex := {}                             # 그림 경로 → 텍스처 (이 재생 화면만의 캐시)

var font: Font
var bold: Font
var stage: Control
var back: ColorRect
var bg_rect: TextureRect
var cg_rect: TextureRect
var stand := {}
var box: PanelContainer
var name_lab: Label
var text_lab: RichTextLabel
var choice_box: VBoxContainer
var title_lab: Label
var hint_lab: Label
var skip_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	clip_contents = true
	font = load("res://assets/fonts/Pretendard-Medium.ttf")
	bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	back = ColorRect.new()
	back.color = Color(0, 0, 0, dim_alpha)
	back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	back.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(back)
	stage = Control.new()
	stage.size = STAGE
	stage.mouse_filter = MOUSE_FILTER_IGNORE
	stage.clip_contents = true
	add_child(stage)
	bg_rect = _full_rect()
	for side in ["left", "right"]:
		var tr := TextureRect.new()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE   # 크기·자리는 _place_stand (그림마다 같은 배율)
		tr.size = Vector2(430, 645)
		tr.position = Vector2(40 if side == "left" else STAGE.x - 470, STAGE.y - 645 + 40)
		tr.flip_h = side == "right"
		tr.mouse_filter = MOUSE_FILTER_IGNORE
		stage.add_child(tr)
		stand[side] = tr
	cg_rect = _full_rect()
	box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.08, 0.92)
	sb.border_color = Color(0.95, 0.75, 0.4, 0.8)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(60, 518)
	box.size = Vector2(STAGE.x - 120, 168)
	box.custom_minimum_size = box.size
	box.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(v)
	name_lab = Label.new()
	name_lab.add_theme_font_override("font", bold)
	name_lab.add_theme_font_size_override("font_size", 22)
	name_lab.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	v.add_child(name_lab)
	text_lab = RichTextLabel.new()
	text_lab.bbcode_enabled = true
	text_lab.fit_content = true
	text_lab.scroll_active = false
	text_lab.custom_minimum_size = Vector2(STAGE.x - 172, 96)
	text_lab.add_theme_font_override("normal_font", font)
	text_lab.add_theme_font_override("italics_font", font)
	text_lab.add_theme_font_size_override("normal_font_size", 22)
	text_lab.add_theme_font_size_override("italics_font_size", 22)
	text_lab.mouse_filter = MOUSE_FILTER_IGNORE
	v.add_child(text_lab)
	choice_box = VBoxContainer.new()
	choice_box.add_theme_constant_override("separation", 10)
	choice_box.position = Vector2(STAGE.x * 0.5 - 300, 200)
	choice_box.custom_minimum_size = Vector2(600, 0)
	stage.add_child(choice_box)
	title_lab = _small_label(Vector2(20, 14), Color(0.85, 0.88, 0.95, 0.75))
	hint_lab = _small_label(Vector2(STAGE.x - 400, 694), Color(0.8, 0.83, 0.9, 0.7))
	hint_lab.size = Vector2(320, 20)
	hint_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_lab.text = "클릭 · Space = 다음   Esc = 건너뛰기"
	skip_btn = Button.new()
	skip_btn.text = "건너뛰기 ▶▶"
	skip_btn.add_theme_font_override("font", font)
	skip_btn.add_theme_font_size_override("font_size", 15)
	skip_btn.focus_mode = FOCUS_NONE
	skip_btn.position = Vector2(STAGE.x - 150, 12)
	skip_btn.pressed.connect(skip_all)
	stage.add_child(skip_btn)
	resized.connect(_fit)
	_fit()
	_clear_stage()


func _full_rect() -> TextureRect:
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.size = STAGE
	tr.mouse_filter = MOUSE_FILTER_IGNORE
	tr.visible = false
	stage.add_child(tr)
	return tr


func _small_label(pos: Vector2, col: Color) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


func _texture(path: String) -> Texture2D:
	if path == "":
		return null
	if not _tex.has(path):
		_tex[path] = CutsceneData.texture(path)
	return _tex[path]


## 그림 파일을 바꿨을 때 (에디터 탭을 다시 열 때)
func clear_textures() -> void:
	_tex.clear()


## 크기에 맞춰 1280x720 무대를 줄이고 가운데
func _fit() -> void:
	if stage == null:
		return
	var s := minf(size.x / STAGE.x, size.y / STAGE.y) if size.x >= 1.0 and size.y >= 1.0 else 1.0
	s = maxf(s, 0.05)   # 크기 0 (배치 전) 일 때 배율 0 이 되지 않게
	stage.scale = Vector2(s, s)
	stage.position = (size - STAGE * s) * 0.5


func _clear_stage() -> void:
	slots = {"left": "", "right": ""}
	poses = {"left": "", "right": ""}
	bg_rect.visible = false
	cg_rect.visible = false
	back.color.a = dim_alpha
	for s in stand:
		stand[s].texture = null
	box.visible = false
	_clear_choices()


func _clear_choices() -> void:
	_waiting_choice = false
	for c in choice_box.get_children():
		choice_box.remove_child(c)
		c.queue_free()


# ================================================================ 재생
## id 컷씬을 from 번째 컷부터 (앞 컷의 배경·CG·서 있는 대원은 그대로 적용, 행동은 안 함)
func play(id: String, from: int = 0) -> void:
	_visited.clear()
	_start(id, from)


func _start(id: String, from: int = 0) -> void:
	if not defs.has(id) or _visited.has(id):   # 없는 컷씬 · 돌고 도는 이어지기 = 끝
		_finish()
		return
	_visited[id] = true
	cur = defs[id]
	playing = true
	_clear_stage()
	title_lab.text = "%s · %s" % [CutsceneData.KINDS.get(cur.kind, ""), cur.name]
	var steps: Array = cur.steps
	from = clampi(from, 0, steps.size())
	for i in from:
		_apply_visual(steps[i])
	cutscene_started.emit(id)
	idx = from - 1
	_next()


func _next() -> void:
	_clear_choices()
	idx += 1
	var steps: Array = cur.steps
	if idx >= steps.size():
		if str(cur.next) != "":
			_start(cur.next)
		else:
			_finish()
		return
	var st: Dictionary = steps[idx]
	match str(st.type):
		"say", "narration":
			_apply_visual(st)
			_show_text(st)
		"cg":
			_apply_visual(st)
			if str(st.text) != "":
				_show_text({"type": "narration", "text": st.text})
			else:
				box.visible = false
				_typing = false
		"bg":
			_apply_visual(st)
			_next()
		"choice":
			_show_choice(st)
		"action":
			action_requested.emit(st)
			_next()


func _show_choice(st: Dictionary) -> void:
	_show_text({"type": "narration", "text": st.text})
	_typing = false
	text_lab.visible_characters = -1
	_waiting_choice = true
	for op in st.options:
		var b := Button.new()
		b.text = str(op.text)
		b.add_theme_font_override("font", bold)
		b.add_theme_font_size_override("font_size", 20)
		b.custom_minimum_size = Vector2(600, 52)
		b.focus_mode = FOCUS_NONE
		for st_name in ["normal", "hover", "pressed"]:
			var bs := StyleBoxFlat.new()
			bs.bg_color = Color(0.06, 0.07, 0.1, 0.94) if st_name == "normal" else Color(0.22, 0.17, 0.08, 0.96)
			bs.border_color = Color(0.95, 0.75, 0.4, 0.9 if st_name != "normal" else 0.55)
			bs.set_border_width_all(2)
			bs.set_corner_radius_all(8)
			b.add_theme_stylebox_override(st_name, bs)
		b.add_theme_color_override("font_hover_color", Color(1, 0.9, 0.6))
		var nx := str(op.next)
		b.pressed.connect(func(): _choose(nx))
		choice_box.add_child(b)


func _choose(nx: String) -> void:
	_clear_choices()
	if nx != "":
		_start(nx)
	else:
		_next()


## 그림 상태만 바꿈 (배경 · CG · 서 있는 대원)
func _apply_visual(st: Dictionary) -> void:
	match str(st.type):
		"bg":
			var t := _texture(str(st.image))
			bg_rect.texture = t
			bg_rect.visible = t != null
			back.color.a = 1.0 if t != null else dim_alpha
			cg_rect.visible = false   # 배경을 바꾸면 CG 는 꺼짐
			_update_stands("")
		"cg":
			var t2 := _texture(str(st.image))
			cg_rect.texture = t2
			cg_rect.visible = t2 != null
			_update_stands("")
		"say":
			var side := str(st.side)
			var sp := str(st.speaker)
			if sp != "":
				for s in slots:   # 같은 대원이 반대편에 서 있었으면 옮김
					if slots[s] == sp and s != side:
						slots[s] = ""
				slots[side] = sp
				poses[side] = str(st.get("pose", ""))
			_update_stands(side)
		"narration":
			_update_stands("")


## 서 있는 대원 그림 (말하는 쪽 밝게). CG 가 떠 있으면 숨김
func _update_stands(active: String) -> void:
	for s in slots:
		var spr := str(npcs.get(slots[s], {}).get("sprite", ""))
		var pose := str(poses.get(s, ""))
		var path := CharacterSprite2D.pose_path(spr, pose) if spr != "" else ""
		if path == "":
			path = "res://assets/characters/%s/base.png" % spr
			pose = ""
		stand[s].texture = CharacterSprite2D._tex(path) if spr != "" and slots[s] != "" else null
		_place_stand(s, spr, pose)
		stand[s].modulate = Color.WHITE if s == active else DIM
		stand[s].visible = not cg_rect.visible


## 서 있는 그림 자리: 기본 그림을 칸(430×645)에 맞춘 배율 그대로, 포즈 그림도 같은 배율 · 같은 발 위치 (누운 그림은 바닥에)
func _place_stand(side: String, spr: String, pose: String) -> void:
	var tr: TextureRect = stand[side]
	var box := Rect2(Vector2(40 if side == "left" else STAGE.x - 470, STAGE.y - 645 + 40), Vector2(430, 645))
	var tex := tr.texture
	if tex == null:
		tr.position = box.position
		tr.size = box.size
		return
	var inf := CharacterSprite2D.info_of(spr)
	var isz: Array = inf.get("image_size", [tex.get_width(), tex.get_height()])
	var k := minf(box.size.x / float(isz[0]), box.size.y / float(isz[1]))
	var g0: Array = inf.get("ground", [float(isz[0]) * 0.5, float(isz[1])])
	var g: Array = g0
	if pose != "":
		var aj := CharacterSprite2D.dir_of(spr).path_join(pose).path_join("anim.json")
		var o: Variant = JSON.parse_string(FileAccess.get_file_as_string(aj)) if FileAccess.file_exists(aj) else null
		if o is Dictionary and o.get("ground") is Array:
			g = o.ground
	var flip := tr.flip_h
	var base_off := Vector2((box.size.x - float(isz[0]) * k) * 0.5, (box.size.y - float(isz[1]) * k) * 0.5)
	var foot := box.position + base_off + Vector2((float(isz[0]) - float(g0[0])) if flip else float(g0[0]), float(g0[1])) * k
	var sz := Vector2(tex.get_width(), tex.get_height()) * k
	var gx := (float(tex.get_width()) - float(g[0])) if flip else float(g[0])
	tr.size = sz
	tr.position = foot - Vector2(gx, float(g[1])) * k
	tr.position.x = clampf(tr.position.x, 0.0, maxf(0.0, STAGE.x - sz.x))   # 누운 그림처럼 넓으면 화면 안으로


func _show_text(st: Dictionary) -> void:
	box.visible = true
	if str(st.type) == "say":
		var nm := str(st.name) if str(st.name) != "" else str(npcs.get(st.speaker, {}).get("name", st.speaker))
		name_lab.text = nm
		name_lab.visible = true
		text_lab.text = str(st.text)
	else:
		name_lab.visible = false
		text_lab.text = "[i][color=#d8dcea]%s[/color][/i]" % st.text
	_shown = 0.0
	text_lab.visible_characters = 0
	_typing = true


func _process(delta: float) -> void:
	if not _typing:
		return
	_shown += delta * CPS
	var total := text_lab.get_total_character_count()
	text_lab.visible_characters = int(_shown)
	if int(_shown) >= total:
		text_lab.visible_characters = -1
		_typing = false


## 클릭 · Space: 글이 나오는 중이면 다 보이기, 아니면 다음 컷
func advance() -> void:
	if not playing or _waiting_choice:
		return
	if _typing:
		_typing = false
		text_lab.visible_characters = -1
		return
	_next()


## 끝까지: 남은 행동 컷은 적용, 선택지는 '끝'(그 컷씬 다음 컷)으로, 이어지는 컷씬도 '본 컷씬' 으로
func skip_all() -> void:
	if not playing:
		return
	_clear_choices()
	_typing = false
	var guard := 0
	while playing and guard < 2000:
		guard += 1
		idx += 1
		var steps: Array = cur.steps
		if idx >= steps.size():
			if str(cur.next) != "" and defs.has(cur.next) and not _visited.has(cur.next):
				_visited[cur.next] = true
				cur = defs[cur.next]
				idx = -1
				cutscene_started.emit(cur.id)
				continue
			_finish()
			return
		var st: Dictionary = steps[idx]
		if st.type == "action":
			action_requested.emit(st)
	_finish()


func _finish() -> void:
	if not playing and cur.is_empty():
		finished.emit("")
		return
	playing = false
	_typing = false
	finished.emit(str(cur.get("id", "")))


## 에디터 미리보기: 그 컷까지 그림 상태 + 그 컷의 글 (재생 안 함)
func show_at(id: String, i: int) -> void:
	if not defs.has(id):
		_clear_stage()
		title_lab.text = ""
		return
	cur = defs[id]
	_visited = {id: true}
	_clear_stage()
	title_lab.text = "%s · %s" % [CutsceneData.KINDS.get(cur.kind, ""), cur.name]
	var steps: Array = cur.steps
	if steps.is_empty():
		return
	i = clampi(i, 0, steps.size() - 1)
	for k in i + 1:
		_apply_visual(steps[k])
	idx = i
	playing = true
	var st: Dictionary = steps[i]
	match str(st.type):
		"say", "narration":
			_show_text(st)
		"cg":
			if str(st.text) != "":
				_show_text({"type": "narration", "text": st.text})
		"choice":
			_show_choice(st)
		"action":
			_show_text({"type": "narration", "text": "(행동 — 화면에는 안 보임) " + CutsceneData.step_text(st)})
		"bg":
			_show_text({"type": "narration", "text": "(배경 바꿈 — 바로 다음 컷으로)"})
	_typing = false
	text_lab.visible_characters = -1


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance()
		accept_event()


func _input(event: InputEvent) -> void:
	if not keys or not playing or not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				advance()
				get_viewport().set_input_as_handled()
			KEY_ESCAPE:
				skip_all()
				get_viewport().set_input_as_handled()
