@tool
extends Control
## 리깅 탭 가운데 그림판: 파츠·뼈를 그리고 마우스로 편집. 좌표는 리그 원화 픽셀 (rig.json 과 같음).
## 휠 = 확대/축소, 가운데·오른쪽 버튼 끌기 = 화면 이동.
## 파츠 모드: 클릭 = 파츠 선택, 끌기 = 옮기기 (방향키 1px, Shift+방향키 10px)
## 뼈 모드: 관절 끌기 = 뼈 위치 (Shift = 자식 뼈도 같이), Ctrl+클릭 = 선택한 뼈의 자식 뼈 추가, 하늘색 십자 = 발 위치
## 포즈 모드: 관절 끌기 = 그 뼈 회전 (저장 안 됨, 피벗 확인용)

var ed   # RigEditorPanel
var zoom := 0.8
var pan := Vector2(60, 20)
var _drag := ""
var _start := Vector2.ZERO
var _orig: Variant = null
var _ang0 := 0.0
var _undo_pushed := false


func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP


func view() -> Transform2D:
	return Transform2D(Vector2(zoom, 0), Vector2(0, zoom), pan)


func to_img(p: Vector2) -> Vector2:
	return (p - pan) / zoom


func to_scr(p: Vector2) -> Vector2:
	return p * zoom + pan


func fit() -> void:
	if ed == null or ed.rig.is_empty():
		return
	var isz: Array = ed.rig.get("image_size", [512, 768])
	var w := float(isz[0])
	var h := float(isz[1])
	zoom = clampf(minf((size.x - 40) / w, (size.y - 40) / h), 0.05, 8.0)
	pan = (size - Vector2(w, h) * zoom) * 0.5
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.14, 0.17))
	if ed == null or ed.rig.is_empty():
		draw_string(get_theme_default_font(), Vector2(20, 40), "위에서 캐릭터를 고르거나 '새 캐릭터' → '파츠 가져오기'", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.8, 0.85, 0.9))
		return
	var isz: Array = ed.rig.get("image_size", [512, 768])
	draw_rect(Rect2(to_scr(Vector2.ZERO), Vector2(float(isz[0]), float(isz[1])) * zoom), Color(0.2, 0.21, 0.25))
	# 참고 그림 (반투명)
	if ed.ref_tex != null and ed.show_ref:
		draw_set_transform_matrix(view() * Transform2D(0.0, ed.ref_origin))
		draw_texture(ed.ref_tex, Vector2.ZERO, Color(1, 1, 1, ed.ref_alpha))
	# 파츠
	for p in ed.draw_order():
		var t: Texture2D = ed.tex.get(p.name)
		if t == null:
			continue
		var xf: Transform2D = ed.part_xform(p)
		draw_set_transform_matrix(view() * xf)
		var col := Color(1, 1, 1, 1)
		if ed.mode != "parts" and ed.sel_bone != "" and p.bone != ed.sel_bone:
			col = Color(1, 1, 1, 0.55)
		draw_texture(t, Vector2.ZERO, col)
		if p.name == ed.sel_part:
			draw_rect(Rect2(Vector2.ZERO, t.get_size()), Color(1, 0.85, 0.2), false, 2.0 / zoom)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	# 발 위치 (ground)
	var g: Array = ed.rig.get("ground", [0, 0])
	var gp := to_scr(Vector2(float(g[0]), float(g[1])))
	draw_line(gp + Vector2(-14, 0), gp + Vector2(14, 0), Color(0.3, 0.9, 1.0), 2.0)
	draw_line(gp + Vector2(0, -14), gp + Vector2(0, 14), Color(0.3, 0.9, 1.0), 2.0)
	# 뼈
	if ed.mode != "parts" or ed.show_bones_always:
		var gl: Dictionary = ed.bone_globals()
		for b in ed.rig.get("bones", []):
			var p0: Vector2 = to_scr((gl[b.name] as Transform2D).origin)
			if str(b.parent) != "" and gl.has(b.parent):
				var p1: Vector2 = to_scr((gl[b.parent] as Transform2D).origin)
				draw_line(p1, p0, Color(1, 0.95, 0.3, 0.9), 3.0)
		for b in ed.rig.get("bones", []):
			var p0: Vector2 = to_scr((gl[b.name] as Transform2D).origin)
			var sel: bool = b.name == ed.sel_bone
			draw_circle(p0, 9.0 if sel else 6.0, Color(1, 0.3, 0.9) if sel else Color(0.9, 0.2, 0.75))
			draw_circle(p0, 9.0 if sel else 6.0, Color(0, 0, 0), false, 1.5)
			if ed.show_names or sel:
				draw_string_outline(get_theme_default_font(), p0 + Vector2(10, -6), str(b.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 3, Color(0, 0, 0))
				draw_string(get_theme_default_font(), p0 + Vector2(10, -6), str(b.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1))
	var help: String = {"parts": "파츠 배치: 클릭 선택 · 끌어서 이동 · 방향키 1px (Shift 10px)",
		"bones": "뼈 편집: 관절 끌기 (Shift = 자식도 함께) · Ctrl+클릭 = 자식 뼈 추가 · 하늘색 십자 = 발 위치",
		"pose": "포즈 테스트: 관절을 끌어 돌려 보기 (저장 안 됨) — 파츠가 관절에서 자연스럽게 도는지 확인"}.get(ed.mode, "")
	draw_string_outline(get_theme_default_font(), Vector2(10, size.y - 10), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
	draw_string(get_theme_default_font(), Vector2(10, size.y - 10), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.92, 1.0))


func _gui_input(event: InputEvent) -> void:
	if ed == null or ed.rig.is_empty():
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var nz := clampf(zoom * (1.15 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15), 0.05, 12.0)
			pan = mb.position - (mb.position - pan) * (nz / zoom)
			zoom = nz
			queue_redraw()
			accept_event()
			return
		if mb.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]:
			_drag = "pan" if mb.pressed else ""
			_start = mb.position
			_orig = pan
			accept_event()
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				grab_focus()
				_press(mb)
			else:
				if _drag in ["part", "bone", "ground"]:
					ed.changed_by_canvas()
				_drag = ""
				_undo_pushed = false
			accept_event()
	elif event is InputEventMouseMotion and _drag != "":
		_motion((event as InputEventMouseMotion).position)
		accept_event()
	elif event is InputEventKey and event.pressed:
		var k := event as InputEventKey
		var d := Vector2.ZERO
		match k.keycode:
			KEY_LEFT: d = Vector2(-1, 0)
			KEY_RIGHT: d = Vector2(1, 0)
			KEY_UP: d = Vector2(0, -1)
			KEY_DOWN: d = Vector2(0, 1)
		if d != Vector2.ZERO:
			ed.nudge(d * (10.0 if k.shift_pressed else 1.0))
			accept_event()


func _press(mb: InputEventMouseButton) -> void:
	var ip := to_img(mb.position)
	_start = ip
	match ed.mode:
		"parts":
			var name: String = ed.hit_part(ip)
			ed.select_part(name)
			if name != "":
				var p: Dictionary = ed.part(name)
				_orig = Vector2(float(p.origin[0]), float(p.origin[1]))
				_drag = "part"
		"bones":
			var g: Array = ed.rig.get("ground", [0, 0])
			if mb.position.distance_to(to_scr(Vector2(float(g[0]), float(g[1])))) < 12.0:
				_drag = "ground"
				_orig = Vector2(float(g[0]), float(g[1]))
				return
			var b: String = ed.bone_at(mb.position, self)
			if b == "" and mb.ctrl_pressed:
				ed.add_bone(ip)
				return
			ed.select_bone(b)
			if b == "":
				ed.select_part(ed.hit_part(ip))
				return
			_drag = "bone"
			var origs := {}
			var targets: Array = ed.subtree(b) if mb.shift_pressed else [b]
			for n in targets:
				var bb: Dictionary = ed.bone(n)
				origs[n] = Vector2(float(bb.pos[0]), float(bb.pos[1]))
			_orig = origs
		"pose":
			var b2: String = ed.bone_at(mb.position, self)
			ed.select_bone(b2)
			if b2 != "":
				_drag = "rot"
				var j: Vector2 = to_scr((ed.bone_globals()[b2] as Transform2D).origin)
				_ang0 = (mb.position - j).angle()
				_orig = float(ed.pose.get(b2, 0.0))


func _motion(pos: Vector2) -> void:
	if _drag == "pan":
		pan = (_orig as Vector2) + (pos - _start)
		queue_redraw()
		return
	if not _undo_pushed and _drag in ["part", "bone", "ground"]:
		ed.push_undo()
		_undo_pushed = true
	var d := (to_img(pos) - _start).round()
	match _drag:
		"part":
			var p: Dictionary = ed.part(ed.sel_part)
			var o: Vector2 = (_orig as Vector2) + d
			p.origin = [int(o.x), int(o.y)]
		"bone":
			for n in (_orig as Dictionary):
				var o2: Vector2 = (_orig as Dictionary)[n] + d
				ed.bone(n).pos = [o2.x, o2.y]
		"ground":
			var o3: Vector2 = (_orig as Vector2) + d
			ed.rig.ground = [int(o3.x), int(o3.y)]
		"rot":
			var j: Vector2 = to_scr((ed.bone_globals()[ed.sel_bone] as Transform2D).origin)
			ed.pose[ed.sel_bone] = float(_orig) + wrapf((pos - j).angle() - _ang0, -PI, PI)
	queue_redraw()
	ed.canvas_moved()
