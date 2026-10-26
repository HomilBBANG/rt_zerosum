@tool
extends Control
## 리깅 에디터 (Godot 에디터 상단 "리깅" 탭, addons/rtz_rig_editor) — 캐릭터 Skeleton2D 리그를 직접 만든다.
## 결과는 게임이 그대로 쓰는 assets/sprites/rig_<id>/ (rig.json + 파츠 PNG + 조명 마스크 + 실루엣 + 초상화).
##
## 순서: 캐릭터 고르기(또는 새 캐릭터) → 파츠 가져오기 → [파츠] 모드로 배치 → [뼈] 모드로 관절 위치 → [포즈]로 돌려 보기 → 저장(Ctrl+S)
## 파츠 가져오기:
##   · 레이어마다 따로 내보낸 PNG 여러 장 (모두 같은 캔버스 크기면 그 자리 그대로 조립됨 — 포토샵·클립 스튜디오 '레이어를 파일로')
##   · 크기가 제각각인 PNG 여러 장 → 옆으로 늘어놓음 (끌어서 배치)
##   · 파츠를 펼쳐 놓은 시트 한 장 → 떨어진 조각마다 파츠, 가장 큰 조각(원본 전신)은 반투명 참고 그림
## 파일 이름이 파츠 이름: head, torso, hips, arm_upper_l, arm_lower_l, hand_l, thigh_l, shin_l, foot_l … (_l = 화면 왼쪽)
## 게임 애니메이션이 쓰는 뼈 이름: hip, spine, chest, head, shoulder_l/r, elbow_l/r, wrist_l/r, hip_l/r, knee_l/r, ankle_l/r ('기본 뼈대')
## 눈동자: 홍채 파츠에 '눈동자' 체크 → 붙을 파츠(머리) · 자를 모양(흰자 파츠) · 움직임 px. 게임에서 흰자 안에서 시선이 움직임.

const TOOLS := preload("res://addons/rtz_rig_editor/rig_tools.gd")
const CANVAS := preload("res://addons/rtz_rig_editor/rig_canvas.gd")
const ROOT := "res://assets/sprites"
const SPECIAL := ["silhouette", "portrait", "_debug_parts", "_debug_mask_r", "_ref"]

var rig_id := ""
var rig: Dictionary = {}
var tex: Dictionary = {}      # 파츠 이름 → Texture2D
var img: Dictionary = {}      # 파츠 이름 → Image
var pose: Dictionary = {}     # 뼈 이름 → 회전 (포즈 모드 미리보기)
var mode := "parts"
var sel_part := ""
var sel_bone := ""
var dirty := false
var show_names := true
var show_bones_always := false
var ref_tex: Texture2D = null
var ref_img: Image = null
var ref_origin := Vector2.ZERO
var ref_alpha := 0.35
var show_ref := true
var height_cm := 175.0
var _undo: Array = []
var _loaded_part_files: Array = []
var _rebuilding := false

var char_list: OptionButton
var status: Label
var canvas: Control
var mode_btns: Dictionary = {}
var part_list: ItemList
var part_box: VBoxContainer
var bone_list: ItemList
var bone_box: VBoxContainer
var preview_vp: SubViewport
var preview_holder: Node2D
var preview_rig: RiggedUnit2D = null
var file_dialog: FileDialog
var new_id: LineEdit


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = 8
	root.offset_right = -8
	root.offset_top = 6
	root.offset_bottom = -6
	add_child(root)
	# ---- 위 막대
	var top := HFlowContainer.new()   # 좁은 화면에서는 줄바꿈
	top.add_theme_constant_override("h_separation", 6)
	top.add_theme_constant_override("v_separation", 4)
	root.add_child(top)
	var title := Label.new()
	title.text = "리깅"
	title.add_theme_font_size_override("font_size", 20)
	top.add_child(title)
	char_list = OptionButton.new()
	char_list.custom_minimum_size.x = 160
	char_list.item_selected.connect(func(i): _confirm_switch(str(char_list.get_item_metadata(i))))
	top.add_child(char_list)
	new_id = LineEdit.new()
	new_id.placeholder_text = "새 캐릭터 id (영문)"
	new_id.custom_minimum_size.x = 140
	top.add_child(new_id)
	top.add_child(_btn("새 캐릭터", _new_character))
	top.add_child(_btn("파츠 가져오기…", func(): file_dialog.popup_centered_ratio(0.6)))
	top.add_child(VSeparator.new())
	for m in [["parts", "파츠"], ["bones", "뼈"], ["pose", "포즈"]]:
		var b := Button.new()
		b.text = m[1]
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _set_mode(m[0]))
		mode_btns[m[0]] = b
		top.add_child(b)
	top.add_child(VSeparator.new())
	top.add_child(_btn("저장 (Ctrl+S)", save))
	top.add_child(_btn("되돌리기 (Ctrl+Z)", undo))
	top.add_child(_btn("다시 읽기", func(): load_rig(rig_id)))
	top.add_child(_btn("화면 맞춤", func(): canvas.fit()))
	top.add_child(_btn("전투에서 보기", func(): _play(false)))
	top.add_child(_btn("기지에서 보기", func(): _play(true)))
	status = Label.new()
	status.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	top.add_child(status)
	# ---- 본문: 왼쪽 목록 | 그림판 | 미리보기
	var body := HSplitContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var left_scroll := ScrollContainer.new()
	left_scroll.custom_minimum_size.x = 300
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(left_scroll)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	left.add_child(_head("파츠 (위 = 앞)"))
	part_list = ItemList.new()
	part_list.custom_minimum_size.y = 230
	part_list.item_selected.connect(func(i): select_part(str(part_list.get_item_metadata(i))))
	left.add_child(part_list)
	var pb := HFlowContainer.new()
	left.add_child(pb)
	pb.add_child(_btn("앞으로 ▲", func(): _move_z(1)))
	pb.add_child(_btn("뒤로 ▼", func(): _move_z(-1)))
	pb.add_child(_btn("삭제", _delete_part))
	pb.add_child(_btn("참고 그림으로", _part_to_ref))
	part_box = VBoxContainer.new()
	left.add_child(part_box)
	left.add_child(HSeparator.new())
	left.add_child(_head("뼈"))
	bone_list = ItemList.new()
	bone_list.custom_minimum_size.y = 230
	bone_list.item_selected.connect(func(i): select_bone(str(bone_list.get_item_metadata(i))))
	left.add_child(bone_list)
	var bb := HFlowContainer.new()
	left.add_child(bb)
	bb.add_child(_btn("기본 뼈대", _template_bones))
	bb.add_child(_btn("파츠↔뼈 자동 연결", _auto_assign))
	bb.add_child(_btn("뼈 추가", func(): add_bone(Vector2.INF)))
	bb.add_child(_btn("뼈 삭제", _delete_bone))
	bone_box = VBoxContainer.new()
	left.add_child(bone_box)
	left.add_child(HSeparator.new())
	left.add_child(_head("보기"))
	left.add_child(_check("뼈 이름", true, func(v): show_names = v; canvas.queue_redraw()))
	left.add_child(_check("파츠 모드에서도 뼈 보기", false, func(v): show_bones_always = v; canvas.queue_redraw()))
	left.add_child(_check("참고 그림", true, func(v): show_ref = v; canvas.queue_redraw()))
	var ra := HSlider.new()
	ra.min_value = 0.05
	ra.max_value = 1.0
	ra.step = 0.05
	ra.value = ref_alpha
	ra.value_changed.connect(func(v): ref_alpha = v; canvas.queue_redraw())
	left.add_child(_small("참고 그림 투명도"))
	left.add_child(ra)
	left.add_child(_btn("발 위치 자동 (그림 맨 아래 가운데)", _auto_ground))
	left.add_child(_small("하늘색 십자 = 발 위치(뼈 모드에서 끌기). 화면 키 = 발 위치 − 그림 맨 위."))
	canvas = CANVAS.new()
	canvas.ed = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(400, 400)
	body.add_child(canvas)
	# 미리보기 (게임과 같은 RiggedUnit2D, 저장한 파일로)
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 340
	body.add_child(right)
	right.add_child(_head("미리보기 (저장한 리그, 게임과 같은 코드)"))
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(330, 560)
	svc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(svc)
	preview_vp = SubViewport.new()
	preview_vp.size = Vector2i(330, 560)
	preview_vp.transparent_bg = false
	svc.add_child(preview_vp)
	var bg := ColorRect.new()
	bg.color = Color(0.32, 0.36, 0.4)
	bg.size = Vector2(2000, 2000)
	preview_vp.add_child(bg)
	preview_holder = Node2D.new()
	preview_vp.add_child(preview_holder)
	var ab := HFlowContainer.new()
	right.add_child(ab)
	for a in ["idle", "walk", "attack", "hit", "heal", "death", "sit"]:
		ab.add_child(_btn(a, func(): _preview_play(a)))
	var hrow := HBoxContainer.new()
	right.add_child(hrow)
	hrow.add_child(_small("키(cm)"))
	var hs := SpinBox.new()
	hs.min_value = 100
	hs.max_value = 400
	hs.value = height_cm
	hs.value_changed.connect(func(v): height_cm = v; _refresh_preview())
	hrow.add_child(hs)
	hrow.add_child(_btn("좌우 반전", func(): _refresh_preview(true)))
	right.add_child(_small("눈동자는 미리보기·게임에서 흰자 안에서 저절로 움직입니다."))
	# 파일 고르기
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILES
	file_dialog.filters = PackedStringArray(["*.png, *.webp ; 그림"])
	file_dialog.title = "파츠 PNG 여러 장, 또는 시트 한 장"
	file_dialog.files_selected.connect(import_files)
	add_child(file_dialog)
	_set_mode("parts")
	reload_list()


# ================================================================ 목록 · 불러오기
func reload_list() -> void:
	char_list.clear()
	var ids: Array = []
	for d in DirAccess.get_directories_at(ROOT):
		if d.begins_with("rig_"):
			ids.append(d.substr(4))
	ids.sort()
	for id in ids:
		char_list.add_item(id)
		char_list.set_item_metadata(char_list.item_count - 1, id)
	if rig_id == "" and not ids.is_empty():
		load_rig(ids[0])
	for i in char_list.item_count:
		if char_list.get_item_metadata(i) == rig_id:
			char_list.select(i)


func _confirm_switch(id: String) -> void:
	if dirty:
		status.text = "저장하지 않은 변경은 버려졌습니다"
	load_rig(id)


func dir() -> String:
	return ROOT.path_join("rig_" + rig_id)


func load_rig(id: String) -> void:
	rig_id = id
	rig = {}
	tex.clear()
	img.clear()
	pose.clear()
	_undo.clear()
	ref_tex = null
	ref_img = null
	sel_part = ""
	sel_bone = ""
	var path := dir().path_join("rig.json")
	if FileAccess.file_exists(path):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if d is Dictionary:
			rig = d
	if rig.is_empty():
		rig = {"image_size": [512, 768], "ground": [256, 760], "figure_px": 760, "scale": 0.312, "bones": [], "parts": [],
			"weapon_bone": "wrist_r", "head_bone": "head"}
	for p in rig.parts:
		var im := _load_img(dir().path_join(str(p.tex)))
		if im != null:
			_set_img(p.name, im)
	_loaded_part_files = rig.parts.map(func(p): return str(p.tex))
	var ref: Dictionary = rig.get("editor_reference", {})
	if not ref.is_empty():
		var ri := _load_img(dir().path_join(str(ref.tex)))
		if ri != null:
			ref_img = ri
			ref_tex = ImageTexture.create_from_image(ri)
			ref_origin = Vector2(float(ref.origin[0]), float(ref.origin[1]))
	dirty = false
	for i in char_list.item_count:
		if char_list.get_item_metadata(i) == id:
			char_list.select(i)
	status.text = "rig_%s 불러옴 (파츠 %d, 뼈 %d)" % [id, rig.parts.size(), rig.bones.size()]
	_rebuild_lists()
	canvas.fit.call_deferred()
	_refresh_preview()


func _load_img(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var im := Image.load_from_file(ProjectSettings.globalize_path(path))
	if im == null or im.is_empty():
		return null
	im.convert(Image.FORMAT_RGBA8)
	return im


func _set_img(name: String, im: Image) -> void:
	img[name] = im
	tex[name] = ImageTexture.create_from_image(im)


func _new_character() -> void:
	var id := new_id.text.strip_edges().to_lower().replace(" ", "_")
	if id == "" or not id.is_valid_identifier():
		status.text = "id 는 영문·숫자·_ 로 (예: kira2)"
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ROOT.path_join("rig_" + id)))
	rig_id = id
	load_rig(id)
	reload_list()
	status.text = "새 캐릭터 rig_%s — '파츠 가져오기'로 시작" % id


# ================================================================ 가져오기
func import_files(paths: PackedStringArray) -> void:
	if rig_id == "":
		status.text = "먼저 캐릭터를 고르거나 새로 만드세요"
		return
	push_undo()
	var items: Array = []   # [{name, img, pos}]
	if paths.size() == 1:
		var im := Image.load_from_file(paths[0])
		im.convert(Image.FORMAT_RGBA8)
		var isl: Array = TOOLS.split_islands(im)
		if isl.size() > 1:
			# 시트: 가장 큰 조각이 다음 것보다 훨씬 크면 원본 전신 → 참고 그림
			var areas := isl.map(func(c): return c.img.get_width() * c.img.get_height())
			var order := range(isl.size())
			order.sort_custom(func(a, b): return areas[a] > areas[b])
			var big: int = order[0]
			if areas[big] > areas[order[1]] * 2.0:
				ref_img = isl[big].img
				ref_tex = ImageTexture.create_from_image(ref_img)
				ref_origin = Vector2(isl[big].pos)
				isl.remove_at(big)
			for i in isl.size():
				items.append({"name": "part_%02d" % (i + 1), "img": isl[i].img, "pos": Vector2(isl[i].pos)})
		else:
			var used := im.get_used_rect()
			items.append({"name": paths[0].get_file().get_basename(), "img": im.get_region(used), "pos": Vector2(used.position)})
	else:
		var same := true
		var first := Vector2i.ZERO
		var loaded: Array = []
		for p in paths:
			var im2 := Image.load_from_file(p)
			if im2 == null or im2.is_empty():
				continue
			im2.convert(Image.FORMAT_RGBA8)
			loaded.append([p, im2])
			if first == Vector2i.ZERO:
				first = im2.get_size()
			elif im2.get_size() != first:
				same = false
		var x := 0.0
		for e in loaded:
			var im3: Image = e[1]
			var used := im3.get_used_rect()
			if used.size.x <= 0:
				continue
			var pos := Vector2(used.position) if same else Vector2(x, 0)
			x += used.size.x + 20
			items.append({"name": str(e[0]).get_file().get_basename(), "img": im3.get_region(used), "pos": pos})
	for it in items:
		var nm := _unique_part_name(_clean(it.name))
		_set_img(nm, it.img)
		rig.parts.append({"name": nm, "bone": "", "tex": nm + ".png", "origin": [int(it.pos.x), int(it.pos.y)],
			"size": [it.img.get_width(), it.img.get_height()], "z": rig.parts.size()})
	_fit_image_size()
	_auto_ground()
	if rig.bones.is_empty():
		_template_bones(false)
	_auto_assign(false)
	_mark()
	_rebuild_lists()
	canvas.fit()
	status.text = "파츠 %d개 가져옴%s — 배치 후 저장" % [items.size(), " (가장 큰 조각은 참고 그림)" if ref_tex != null else ""]


func _clean(n: String) -> String:
	var s := n.strip_edges().replace(" ", "_").replace("-", "_")
	return s if s != "" else "part"


func _unique_part_name(n: String) -> String:
	var names: Array = rig.parts.map(func(p): return str(p.name))
	if not names.has(n) and not n in SPECIAL:
		return n
	var i := 2
	while names.has("%s_%d" % [n, i]):
		i += 1
	return "%s_%d" % [n, i]


func _fit_image_size() -> void:
	var r := _union_rect(false)
	if ref_img != null:
		r = r.merge(Rect2(ref_origin, ref_img.get_size()))
	var w := maxi(64, int(ceil(r.end.x)) + 4)
	var h := maxi(64, int(ceil(r.end.y)) + 4)
	rig.image_size = [w, h]


func _union_rect(include_ref: bool = false) -> Rect2:
	var r := Rect2()
	var first := true
	for p in rig.parts:
		var pr := Rect2(float(p.origin[0]), float(p.origin[1]), float(p.size[0]), float(p.size[1]))
		r = pr if first else r.merge(pr)
		first = false
	if include_ref and ref_img != null:
		r = Rect2(ref_origin, ref_img.get_size()) if first else r.merge(Rect2(ref_origin, ref_img.get_size()))
	return r


# ================================================================ 데이터 도우미 (그림판이 씀)
func part(name: String) -> Dictionary:
	for p in rig.parts:
		if p.name == name:
			return p
	return {}


func bone(name: String) -> Dictionary:
	for b in rig.bones:
		if b.name == name:
			return b
	return {}


func subtree(name: String) -> Array:
	var out := [name]
	var i := 0
	while i < out.size():
		for b in rig.bones:
			if b.parent == out[i] and not out.has(b.name):
				out.append(b.name)
		i += 1
	return out


## 뼈 전역 변환 (포즈 모드면 회전 반영)
func bone_globals() -> Dictionary:
	var out := {}
	var pending: Array = rig.bones.duplicate()
	var guard := 0
	while not pending.is_empty() and guard < 1000:
		guard += 1
		var b: Dictionary = pending.pop_front()
		var par := str(b.parent)
		var pos := Vector2(float(b.pos[0]), float(b.pos[1]))
		var r: float = float(pose.get(b.name, 0.0)) if mode == "pose" else 0.0
		if par == "" or bone(par).is_empty():
			out[b.name] = Transform2D(r, pos)
		elif out.has(par):
			var pb := bone(par)
			var ppos := Vector2(float(pb.pos[0]), float(pb.pos[1]))
			out[b.name] = (out[par] as Transform2D) * Transform2D(r, pos - ppos)
		else:
			pending.append(b)
	return out


func part_xform(p: Dictionary, gl: Dictionary = {}) -> Transform2D:
	var o := Vector2(float(p.origin[0]), float(p.origin[1]))
	if mode != "pose":
		return Transform2D(0.0, o)
	if gl.is_empty():
		gl = bone_globals()
	var host: Dictionary = part(str(p.get("attach", ""))) if p.has("attach") else {}
	var bn := str(host.bone) if not host.is_empty() else str(p.bone)
	if not gl.has(bn):
		return Transform2D(0.0, o)
	var b := bone(bn)
	var bp := Vector2(float(b.pos[0]), float(b.pos[1]))
	return (gl[bn] as Transform2D) * Transform2D(0.0, o - bp)


## 그리는 순서: z 오름차순, 붙은 파츠(눈동자)는 붙을 파츠 바로 뒤
func draw_order() -> Array:
	var base: Array = rig.parts.filter(func(p): return not p.has("attach"))
	base.sort_custom(func(a, b): return int(a.z) < int(b.z))
	var out: Array = []
	for p in base:
		out.append(p)
		for q in rig.parts:
			if str(q.get("attach", "")) == p.name:
				out.append(q)
	for q in rig.parts:
		if q.has("attach") and not out.has(q):
			out.append(q)
	return out


func hit_part(ip: Vector2) -> String:
	var order := draw_order()
	order.reverse()
	var gl := bone_globals()
	for p in order:
		var im: Image = img.get(p.name)
		if im == null:
			continue
		var lp: Vector2 = part_xform(p, gl).affine_inverse() * ip
		var x := int(lp.x)
		var y := int(lp.y)
		if x >= 0 and y >= 0 and x < im.get_width() and y < im.get_height() and im.get_pixel(x, y).a > 0.3:
			return p.name
	return ""


func bone_at(screen: Vector2, cv: Control) -> String:
	var gl := bone_globals()
	var best := ""
	var bd := 12.0
	for b in rig.bones:
		var d: float = screen.distance_to(cv.to_scr((gl[b.name] as Transform2D).origin))
		if d < bd:
			bd = d
			best = b.name
	return best


# ================================================================ 편집
func push_undo() -> void:
	_undo.append(rig.duplicate(true))
	if _undo.size() > 60:
		_undo.pop_front()


func undo() -> void:
	if _undo.is_empty():
		status.text = "되돌릴 것이 없습니다"
		return
	rig = _undo.pop_back()
	_mark()
	_rebuild_lists()


func _mark() -> void:
	dirty = true
	status.text = "수정됨 (저장 안 됨)"
	canvas.queue_redraw()


func changed_by_canvas() -> void:
	_mark()
	_rebuild_props()


func canvas_moved() -> void:
	pass


func nudge(d: Vector2) -> void:
	push_undo()
	if mode == "parts" and sel_part != "":
		var p := part(sel_part)
		p.origin = [int(p.origin[0] + d.x), int(p.origin[1] + d.y)]
	elif mode == "bones" and sel_bone != "":
		var b := bone(sel_bone)
		b.pos = [float(b.pos[0]) + d.x, float(b.pos[1]) + d.y]
	_mark()
	_rebuild_props()


func select_part(name: String) -> void:
	sel_part = name
	for i in part_list.item_count:
		if part_list.get_item_metadata(i) == name:
			part_list.select(i)
	if name == "":
		part_list.deselect_all()
	_rebuild_props()
	canvas.queue_redraw()


func select_bone(name: String) -> void:
	sel_bone = name
	for i in bone_list.item_count:
		if bone_list.get_item_metadata(i) == name:
			bone_list.select(i)
	if name == "":
		bone_list.deselect_all()
	_rebuild_props()
	canvas.queue_redraw()


func _set_mode(m: String) -> void:
	mode = m
	for k in mode_btns:
		mode_btns[k].button_pressed = k == m
	if m != "pose":
		pose.clear()
	canvas.queue_redraw()


func _move_z(d: int) -> void:
	if sel_part == "" or part(sel_part).has("attach"):
		return
	push_undo()
	var base: Array = rig.parts.filter(func(p): return not p.has("attach"))
	base.sort_custom(func(a, b): return int(a.z) < int(b.z))
	var i: int = base.find(part(sel_part))
	var j := clampi(i + d, 0, base.size() - 1)
	if i == j:
		return
	var t = base[i]
	base[i] = base[j]
	base[j] = t
	for k in base.size():
		base[k].z = k
	_mark()
	_rebuild_lists()


func _delete_part() -> void:
	if sel_part == "":
		return
	push_undo()
	rig.parts.erase(part(sel_part))
	for q in rig.parts:
		if str(q.get("attach", "")) == sel_part or str(q.get("clip_part", "")) == sel_part:
			q.erase("attach")
			q.erase("clip_part")
	sel_part = ""
	_mark()
	_rebuild_lists()


func _part_to_ref() -> void:
	if sel_part == "":
		return
	push_undo()
	var p := part(sel_part)
	ref_img = img[sel_part]
	ref_tex = tex[sel_part]
	ref_origin = Vector2(float(p.origin[0]), float(p.origin[1]))
	rig.parts.erase(p)
	sel_part = ""
	_mark()
	_rebuild_lists()


func _rename_part(old: String, nm: String) -> void:
	nm = _clean(nm)
	if nm == old or nm == "" or not part(nm).is_empty():
		return
	push_undo()
	var p := part(old)
	p.name = nm
	p.tex = nm + ".png"
	img[nm] = img[old]
	tex[nm] = tex[old]
	for q in rig.parts:
		if str(q.get("attach", "")) == old:
			q.attach = nm
		if str(q.get("clip_part", "")) == old:
			q.clip_part = nm
	sel_part = nm
	_mark()
	_rebuild_lists()


func _template_bones(undoable: bool = true) -> void:
	if undoable:
		push_undo()
	# 참고 그림(원본 전신)이 있으면 그 위에, 없으면 파츠 전체 범위에 사람 비율로
	var r := Rect2(ref_origin, ref_img.get_size()) if ref_img != null else _union_rect(false)
	if r.size.y <= 0:
		r = Rect2(0, 0, 512, 768)
	rig.bones = TOOLS.template_bones(r)
	sel_bone = ""
	_auto_assign(false)
	_mark()
	_rebuild_lists()
	status.text = "기본 뼈대 16개 — [뼈] 모드에서 관절 위치를 그림에 맞춰 끌어 주세요"


func _auto_assign(undoable: bool = true) -> void:
	if undoable:
		push_undo()
	for p in rig.parts:
		if p.has("attach"):
			continue
		var c := Vector2(float(p.origin[0]) + float(p.size[0]) * 0.5, float(p.origin[1]) + float(p.size[1]) * 0.25)
		p.bone = TOOLS.guess_bone(str(p.name), c, rig.bones)
	_mark()
	_rebuild_props()


func add_bone(at: Vector2) -> void:
	push_undo()
	var par := sel_bone
	var pos := at
	if at == Vector2.INF:
		pos = Vector2(float(rig.image_size[0]) * 0.5, float(rig.image_size[1]) * 0.5)
		if par != "":
			var pb := bone(par)
			pos = Vector2(float(pb.pos[0]) + 30, float(pb.pos[1]) + 30)
	var i := 1
	while not bone("bone_%d" % i).is_empty():
		i += 1
	var nm := "bone_%d" % i
	rig.bones.append({"name": nm, "parent": par, "pos": [snappedf(pos.x, 0.1), snappedf(pos.y, 0.1)]})
	sel_bone = nm
	_mark()
	_rebuild_lists()


func _delete_bone() -> void:
	if sel_bone == "":
		return
	push_undo()
	var b := bone(sel_bone)
	var par := str(b.parent)
	for c in rig.bones:
		if c.parent == sel_bone:
			c.parent = par
	for p in rig.parts:
		if p.bone == sel_bone:
			p.bone = par
	rig.bones.erase(b)
	sel_bone = ""
	_mark()
	_rebuild_lists()


func _rename_bone(old: String, nm: String) -> void:
	nm = nm.strip_edges()
	if nm == old or nm == "" or not bone(nm).is_empty():
		return
	push_undo()
	bone(old).name = nm
	for c in rig.bones:
		if c.parent == old:
			c.parent = nm
	for p in rig.parts:
		if p.bone == old:
			p.bone = nm
	sel_bone = nm
	_mark()
	_rebuild_lists()


func _auto_ground() -> void:
	var r := _union_rect(false)
	if r.size.y <= 0:
		return
	# 맨 아래 줄의 불투명 가운데
	var bottom := r.end.y
	var xs: Array = []
	for p in rig.parts:
		var im: Image = img.get(p.name)
		if im == null:
			continue
		var y := int(bottom - float(p.origin[1])) - 2
		if y < 0 or y >= im.get_height():
			continue
		for x in im.get_width():
			if im.get_pixel(x, y).a > 0.5:
				xs.append(float(p.origin[0]) + x)
	var cx: float = r.get_center().x if xs.is_empty() else (float(xs.min()) + float(xs.max())) * 0.5
	rig.ground = [int(cx), int(bottom) - 1]
	_mark()


# ================================================================ 왼쪽 목록 · 속성
func _rebuild_lists() -> void:
	_rebuilding = true
	part_list.clear()
	var order := draw_order()
	order.reverse()
	for p in order:
		var tag := "  ↳ " if p.has("attach") else ""
		part_list.add_item("%s%s   [%s]" % [tag, p.name, p.bone if str(p.bone) != "" else "뼈 없음"])
		part_list.set_item_metadata(part_list.item_count - 1, p.name)
		if str(p.bone) == "" and not p.has("attach"):
			part_list.set_item_custom_fg_color(part_list.item_count - 1, Color(1, 0.5, 0.4))
	bone_list.clear()
	var depth := {}
	for n in _bone_order():
		var b := bone(n)
		var dpt: int = depth.get(str(b.parent), -1) + 1
		depth[n] = dpt
		bone_list.add_item("  ".repeat(dpt) + n)
		bone_list.set_item_metadata(bone_list.item_count - 1, n)
	_rebuilding = false
	select_part(sel_part)
	select_bone(sel_bone)


func _bone_order() -> Array:
	var out: Array = []
	var roots: Array = rig.bones.filter(func(b): return str(b.parent) == "" or bone(str(b.parent)).is_empty())
	var stack: Array = roots.map(func(b): return str(b.name))
	stack.reverse()
	while not stack.is_empty():
		var n: String = stack.pop_back()
		if out.has(n):
			continue
		out.append(n)
		var kids: Array = rig.bones.filter(func(b): return b.parent == n).map(func(b): return str(b.name))
		kids.reverse()
		stack.append_array(kids)
	return out


func _rebuild_props() -> void:
	for c in part_box.get_children():
		c.queue_free()
	for c in bone_box.get_children():
		c.queue_free()
	if sel_part != "" and not part(sel_part).is_empty():
		var p := part(sel_part)
		var g := GridContainer.new()
		g.columns = 2
		part_box.add_child(g)
		g.add_child(_small("이름"))
		var ne := LineEdit.new()
		ne.text = p.name
		ne.text_submitted.connect(func(t): _rename_part(p.name, t))
		ne.focus_exited.connect(func(): _rename_part(p.name, ne.text))
		g.add_child(ne)
		g.add_child(_small("뼈"))
		g.add_child(_bone_option(str(p.bone), func(v): push_undo(); p.bone = v; _mark(); _rebuild_lists()))
		g.add_child(_small("위치"))
		g.add_child(_small("%d, %d  (크기 %d×%d)" % [p.origin[0], p.origin[1], p.size[0], p.size[1]]))
		var eye := CheckBox.new()
		eye.text = "눈동자 (흰자 안에서 움직임)"
		eye.button_pressed = p.has("attach")
		eye.toggled.connect(func(on):
			push_undo()
			if on:
				var host := ""
				for q in rig.parts:
					if str(q.bone) == "head" and q.name != p.name and not q.has("attach"):
						host = q.name
						break
				p.attach = host
				p.clip_part = ""
				p.eye_range = [4, 1.5]
				p.bone = "head"
			else:
				p.erase("attach")
				p.erase("clip_part")
				p.erase("eye_range")
			_mark()
			_rebuild_lists())
		part_box.add_child(eye)
		if p.has("attach"):
			var g2 := GridContainer.new()
			g2.columns = 2
			part_box.add_child(g2)
			g2.add_child(_small("붙을 파츠 (머리)"))
			g2.add_child(_part_option(str(p.attach), p.name, func(v): push_undo(); p.attach = v; _mark(); _rebuild_lists()))
			g2.add_child(_small("자를 모양 (흰자)"))
			g2.add_child(_part_option(str(p.get("clip_part", "")), p.name, func(v): push_undo(); p.clip_part = v; _mark()))
			var rng: Array = p.get("eye_range", [4, 1.5])
			g2.add_child(_small("움직임 좌우 px"))
			g2.add_child(_spin(rng[0], 0, 40, 0.5, func(v): p.eye_range = [v, p.eye_range[1]]; _mark()))
			g2.add_child(_small("움직임 위아래 px"))
			g2.add_child(_spin(rng[1], 0, 40, 0.5, func(v): p.eye_range = [p.eye_range[0], v]; _mark()))
			part_box.add_child(_small("흰자 파츠 = 눈 테두리 모양 그림 (그 모양 안에서만 눈동자가 보임). 흰자는 머리 그림에 칠해 두거나 별도 파츠로."))
	if sel_bone != "" and not bone(sel_bone).is_empty():
		var b := bone(sel_bone)
		var g3 := GridContainer.new()
		g3.columns = 2
		bone_box.add_child(g3)
		g3.add_child(_small("이름"))
		var be := LineEdit.new()
		be.text = b.name
		be.text_submitted.connect(func(t): _rename_bone(b.name, t))
		be.focus_exited.connect(func(): _rename_bone(b.name, be.text))
		g3.add_child(be)
		g3.add_child(_small("부모 뼈"))
		var set_parent := func(v: String) -> void:
			if v != "" and subtree(b.name).has(v):
				status.text = "자기 자식을 부모로 할 수 없습니다"
				return
			push_undo()
			b.parent = v
			_mark()
			_rebuild_lists()
		g3.add_child(_bone_option(str(b.parent), set_parent, b.name))
		g3.add_child(_small("위치"))
		g3.add_child(_small("%.1f, %.1f" % [b.pos[0], b.pos[1]]))
		var used: Array = rig.parts.filter(func(p): return p.bone == b.name).map(func(p): return str(p.name))
		bone_box.add_child(_small("붙은 파츠: " + (", ".join(used) if not used.is_empty() else "없음")))


func _bone_option(cur: String, cb: Callable, exclude: String = "") -> OptionButton:
	var o := OptionButton.new()
	o.add_item("(없음)")
	o.set_item_metadata(0, "")
	for n in _bone_order():
		if n == exclude:
			continue
		o.add_item(n)
		o.set_item_metadata(o.item_count - 1, n)
		if n == cur:
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i): cb.call(str(o.get_item_metadata(i))))
	return o


func _part_option(cur: String, exclude: String, cb: Callable) -> OptionButton:
	var o := OptionButton.new()
	o.add_item("(없음)")
	o.set_item_metadata(0, "")
	for p in rig.parts:
		if p.name == exclude:
			continue
		o.add_item(p.name)
		o.set_item_metadata(o.item_count - 1, p.name)
		if p.name == cur:
			o.select(o.item_count - 1)
	o.item_selected.connect(func(i): cb.call(str(o.get_item_metadata(i))))
	return o


# ================================================================ 저장
func save() -> void:
	if rig_id == "" or rig.parts.is_empty():
		status.text = "저장할 파츠가 없습니다"
		return
	var d := dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	_fit_image_size()
	var W: int = rig.image_size[0]
	var H: int = rig.image_size[1]
	# 휴식 자세 합성
	var comp := Image.create(W, H, false, Image.FORMAT_RGBA8)
	var saved_mode := mode
	mode = "parts"
	for p in draw_order():
		var im: Image = img.get(p.name)
		if im == null:
			continue
		p.size = [im.get_width(), im.get_height()]
		var clip: Image = null
		if p.has("attach") and str(p.get("clip_part", "")) != "" and img.has(p.clip_part):
			clip = img[p.clip_part]
		if clip == null:
			comp.blend_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(int(p.origin[0]), int(p.origin[1])))
		else:
			var cp := part(p.clip_part)
			var tmp := im.duplicate() as Image
			for y in tmp.get_height():
				for x in tmp.get_width():
					var cx := int(p.origin[0]) + x - int(cp.origin[0])
					var cy := int(p.origin[1]) + y - int(cp.origin[1])
					var a := clip.get_pixel(cx, cy).a if cx >= 0 and cy >= 0 and cx < clip.get_width() and cy < clip.get_height() else 0.0
					var c := tmp.get_pixel(x, y)
					c.a *= a
					tmp.set_pixel(x, y, c)
			comp.blend_rect(tmp, Rect2i(Vector2i.ZERO, tmp.get_size()), Vector2i(int(p.origin[0]), int(p.origin[1])))
	mode = saved_mode
	# 조명 마스크 (전신 기준) → 파츠별
	status.text = "조명 마스크 만드는 중…"
	var mr: Image = TOOLS.zone_mask(comp, true)
	var ml: Image = TOOLS.zone_mask(comp, false)
	var keep := {}
	for p in rig.parts:
		var im: Image = img.get(p.name)
		if im == null:
			continue
		im.save_png(ProjectSettings.globalize_path(d.path_join(p.name + ".png")))
		keep[p.name + ".png"] = true
		var r := Rect2i(int(p.origin[0]), int(p.origin[1]), im.get_width(), im.get_height())
		for pair in [["_mask_r.png", mr], ["_mask_l.png", ml]]:
			var m: Image
			if p.has("attach"):
				m = Image.create(r.size.x, r.size.y, false, Image.FORMAT_L8)
				m.fill(Color8(TOOLS.Z_UNLIT, TOOLS.Z_UNLIT, TOOLS.Z_UNLIT))   # 눈동자 구역 (로스터 eye_paint 가 있으면 그 색)
			else:
				m = Image.create(r.size.x, r.size.y, false, Image.FORMAT_L8)
				m.blit_rect(pair[1], r, Vector2i.ZERO)
			m.save_png(ProjectSettings.globalize_path(d.path_join(p.name + pair[0])))
			keep[p.name + pair[0]] = true
		# 눈동자 자르기 마스크 (흰자 파츠 알파)
		if p.has("attach"):
			p.erase("clip_mask")
			p.erase("clip_origin")
			var cpn := str(p.get("clip_part", ""))
			if cpn != "" and img.has(cpn):
				var cim: Image = img[cpn]
				var cm := Image.create(cim.get_width(), cim.get_height(), false, Image.FORMAT_L8)
				for y in cim.get_height():
					for x in cim.get_width():
						var a := cim.get_pixel(x, y).a
						cm.set_pixel(x, y, Color(a, a, a))
				cm.save_png(ProjectSettings.globalize_path(d.path_join(cpn + "_clip.png")))
				keep[cpn + "_clip.png"] = true
				p.clip_mask = cpn + "_clip.png"
				p.clip_origin = part(cpn).origin
	# 예전 파츠 파일 정리 (이 리그가 쓰던 이름만)
	for f in _loaded_part_files:
		if not keep.has(f):
			for suf in ["", "_mask_r", "_mask_l"]:
				var fp: String = d.path_join(str(f).get_basename() + suf + ".png")
				if FileAccess.file_exists(fp):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(fp))
	_loaded_part_files = rig.parts.map(func(p): return str(p.tex))
	# 키 · 머리 · 눈 · 실루엣 · 초상화
	var used := comp.get_used_rect()
	var g: Array = rig.get("ground", [W / 2, used.end.y])
	rig.figure_px = maxi(1, int(g[1]) - used.position.y)
	var head_r := Rect2i()
	for p in rig.parts:
		if str(p.bone) == "head" and not p.has("attach"):
			var pr := Rect2i(int(p.origin[0]), int(p.origin[1]), int(p.size[0]), int(p.size[1]))
			head_r = pr if head_r.size == Vector2i.ZERO else head_r.merge(pr)
	if head_r.size == Vector2i.ZERO:
		head_r = Rect2i(used.position, Vector2i(used.size.x, used.size.y / 6))
	rig.head_rect = [head_r.position.x, head_r.position.y, head_r.size.x, head_r.size.y]
	rig.eyes = rig.parts.filter(func(p): return p.has("attach")).map(func(p): return [int(p.origin[0]) + int(p.size[0]) / 2, int(p.origin[1]) + int(p.size[1]) / 2])
	var sil := Image.create(W, H, false, Image.FORMAT_RGBA8)
	for y in H:
		for x in W:
			if comp.get_pixel(x, y).a > 0.4:
				sil.set_pixel(x, y, Color(1, 1, 1, 1))
	sil.resize(maxi(1, W / 2), maxi(1, H / 2), Image.INTERPOLATE_BILINEAR)
	sil.save_png(ProjectSettings.globalize_path(d.path_join("silhouette.png")))
	rig.silhouette = "silhouette.png"
	var side := maxi(head_r.size.x, head_r.size.y)
	var pr2 := Rect2i(head_r.get_center().x - side / 2, head_r.position.y, side, side).intersection(Rect2i(0, 0, W, H))
	if pr2.size.x > 0:
		comp.get_region(pr2).save_png(ProjectSettings.globalize_path(d.path_join("portrait.png")))
		rig.portrait = "portrait.png"
	if ref_img != null:
		ref_img.save_png(ProjectSettings.globalize_path(d.path_join("_ref.png")))
		rig.editor_reference = {"tex": "_ref.png", "origin": [int(ref_origin.x), int(ref_origin.y)]}
	else:
		rig.erase("editor_reference")
	rig.weapon_bone = rig.get("weapon_bone", "wrist_r")
	var f := FileAccess.open(d.path_join("rig.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(rig, " "))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().scan()
	dirty = false
	var missing := []
	for need in ["hip", "spine", "chest", "head", "shoulder_l", "shoulder_r", "elbow_l", "elbow_r", "wrist_r", "hip_l", "hip_r", "knee_l", "knee_r"]:
		if bone(need).is_empty():
			missing.append(need)
	var no_bone: Array = rig.parts.filter(func(p): return str(p.bone) == "" or bone(str(p.bone)).is_empty()).map(func(p): return str(p.name))
	status.text = "저장됨: assets/sprites/rig_%s (파츠 %d, 키 %dpx)%s%s" % [rig_id, rig.parts.size(), rig.figure_px,
		("  ⚠ 애니메이션에 없는 뼈: " + ", ".join(missing)) if not missing.is_empty() else "",
		("  ⚠ 뼈 없는 파츠: " + ", ".join(no_bone)) if not no_bone.is_empty() else ""]
	_refresh_preview()


# ================================================================ 미리보기 · 실행
func _refresh_preview(flip: bool = false) -> void:
	if preview_rig != null:
		preview_rig.queue_free()
		preview_rig = null
	if rig_id == "" or not FileAccess.file_exists(dir().path_join("rig.json")):
		return
	var r := RiggedUnit2D.new()
	r.raw_load = true
	preview_holder.add_child(r)
	var mirrored: bool = flip and not bool(preview_holder.get_meta("flipped", false))
	preview_holder.set_meta("flipped", mirrored)
	r.build(dir(), mirrored, height_cm)
	r.set_param("paint_eyes", false)
	r.set_param("key_color", Color(1.0, 0.85, 0.7))
	r.set_param("ambient_tint", Color(0.75, 0.78, 0.85))
	r.set_param("shadow_tint", Color(0.35, 0.38, 0.5))
	r.set_param("accent_color", Color(0.6, 0.9, 1.0))
	var screen_h := 230.0 * height_cm / 175.0
	var k := 470.0 / screen_h
	r.scale = Vector2(k, k)
	r.position = Vector2(165, 530)
	preview_rig = r


func _preview_play(a: String) -> void:
	if preview_rig == null:
		status.text = "먼저 저장하세요 (미리보기는 저장한 리그로)"
		return
	if a in ["walk", "sit", "idle"]:
		preview_rig.anim.play(a if preview_rig.anim.has_animation(a) else "idle")
	else:
		preview_rig.play(a)


func _play(base: bool) -> void:
	if dirty:
		save()
	var f := FileAccess.open(GameData.EDITOR_PLAY_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"base": true}) if base else JSON.stringify({}))
	f.close()
	if Engine.is_editor_hint():
		EditorInterface.play_custom_scene("res://scenes/outgame/base_hub.tscn" if base else "res://scenes/battle_2d.tscn")


func _shortcut_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.pressed:
		return
	var k := event as InputEventKey
	if (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_S:
		save()
		get_viewport().set_input_as_handled()
	elif (k.ctrl_pressed or k.meta_pressed) and k.keycode == KEY_Z:
		undo()
		get_viewport().set_input_as_handled()


# ================================================================ 작은 위젯
func _btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _check(t: String, on: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = t
	c.button_pressed = on
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(cb)
	return c


func _spin(v: float, lo: float, hi: float, step: float, cb: Callable) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.value_changed.connect(cb)
	return s


func _small(t: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = t
	if wrap and t.length() > 14:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 120
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", Color(0.78, 0.8, 0.88))
	return l


func _head(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(1, 0.95, 0.75))
	return l
