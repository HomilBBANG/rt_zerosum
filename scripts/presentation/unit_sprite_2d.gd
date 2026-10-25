class_name UnitSprite2D
extends Node2D
## 2D 유닛: 원화 스프라이트 + 구역 마스크 셰이더 + 무기 레이어 + 클릭 영역 + 하이라이트.

signal clicked(unit: UnitRuntime)

const SHADER := preload("res://shaders/cel_character.gdshader")
const OUTLINE_SHADER := preload("res://shaders/outline_group.gdshader")
const RIG_SCRIPT := preload("res://scripts/presentation/rigged_unit_2d.gd")
const BASE_SCALE := 0.5


var unit: UnitRuntime
var manifest: Dictionary
var body: Sprite2D
var weapon: Sprite2D
var flip: Node2D
var group: CanvasGroup
var area: Area2D
var mat: ShaderMaterial
var wmat: ShaderMaterial
var highlight_kind: String = "none"
var light_from_right: bool = true
var _bob_t: float = 0.0
var _flash: float = 0.0
var _dead_alpha: float = 1.0
var ui_accent: Color = Color(1, 0.9, 0.4)
var rig: RiggedUnit2D = null
var rig_height: float = 232.0
const PX_PER_M := 230.0 / 1.75   # 리그 키 230px = 1.75m (스프라이트 로컬 픽셀)
var _lm_tex: ImageTexture = null
var _lm_local := Rect2()
var _lm_xf := Transform2D()
var _face_band := Vector2(-1, -1)


func is_rigged() -> bool:
	return rig != null


func build(p_unit: UnitRuntime, p_manifest: Dictionary) -> void:
	unit = p_unit
	manifest = p_manifest
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	# 파츠·무기를 하나의 CanvasGroup 으로 그려 합쳐진 실루엣에 외곽선을 준다
	group = CanvasGroup.new()
	group.name = "Group"
	group.fit_margin = 8.0
	group.clear_margin = 8.0
	var om := ShaderMaterial.new()
	om.shader = OUTLINE_SHADER
	if Game.cli.get("outline", "1") != "0":
		group.material = om
	flip = Node2D.new()
	flip.name = "Flip"
	if Game.cli.get("nogroup", "0") == "1":
		add_child(flip)
	else:
		add_child(group)
		group.add_child(flip)
	if unit.team == "enemy":
		flip.scale.x = -1.0
	flip.scale *= BASE_SCALE
	if UnitArt.has_rig(unit.data.sprite_id):
		_build_rigged(meta)
		return
	body = Sprite2D.new()
	body.name = "Body"
	body.centered = false
	body.texture = load("res://assets/sprites/%s.png" % unit.data.sprite_id)
	var ground: float = float(meta.get("ground", 492))
	body.offset = Vector2(-128.0, -ground)
	body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mat = ShaderMaterial.new()
	mat.shader = SHADER
	body.material = mat
	flip.add_child(body)
	weapon = Sprite2D.new()
	weapon.name = "Weapon"
	weapon.centered = false
	wmat = ShaderMaterial.new()
	wmat.shader = SHADER
	weapon.material = wmat
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var hand: Array = meta.get("hand", [172, 298])
	weapon.position = Vector2(float(hand[0]) - 128.0, float(hand[1]) - ground)
	flip.add_child(weapon)
	refresh_weapon()
	# 클릭 영역
	area = Area2D.new()
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	var h: float = float(meta.get("height", 460)) * BASE_SCALE
	rect.size = Vector2(120.0 * BASE_SCALE * 1.6, h)
	shape.shape = rect
	shape.position = Vector2(0, -h * 0.5)
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)
	_update_light_masks()
	z_index = 10

## Skeleton2D 리그 경로: 파츠별 셰이더/마스크, 무기는 손 본에 부착
func _build_rigged(_meta: Dictionary) -> void:
	rig = RIG_SCRIPT.new()
	rig.name = "Rig"
	flip.add_child(rig)
	rig.scale = Vector2.ONE / BASE_SCALE
	rig.build(UnitArt.rig_dir(unit.data.sprite_id), false, unit.data.height_cm)
	rig_height = -rig.head_top_local().y + 6.0
	mat = rig.mats[0]
	weapon = Sprite2D.new()
	weapon.name = "Weapon"
	weapon.centered = false
	wmat = ShaderMaterial.new()
	wmat.shader = SHADER
	weapon.material = wmat
	weapon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	rig.attach_weapon(weapon)
	# 무기 원화는 캐릭터 키 460px 기준 → 리그 원화 픽셀계로 (키 230px 화면 = 리그 scale)
	weapon.scale = Vector2.ONE * (0.5 / rig.scale_factor)
	weapon.z_index = 9
	refresh_weapon()
	area = Area2D.new()
	area.input_pickable = true
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(110.0, rig_height)
	shape.shape = rect
	shape.position = Vector2(0, -rig_height * 0.5)
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)
	_update_light_masks()
	z_index = 10


func _all_mats() -> Array:
	if rig != null:
		var arr: Array = rig.mats.duplicate()
		arr.append(wmat)
		return arr
	return [mat, wmat]


func refresh_weapon() -> void:
	var w := unit.current_weapon()
	var wid: String = w.get("id", "")
	var path := "res://assets/sprites/w_%s.png" % wid
	if wid == "" or not ResourceLoader.exists(path):
		weapon.visible = false
		return
	weapon.visible = true
	weapon.texture = load(path)
	var wm: Dictionary = manifest.weapons.get(wid, {"pivot": [0, 0]})
	weapon.offset = Vector2(-float(wm.pivot[0]), -float(wm.pivot[1]))
	_update_light_masks()


func set_light_direction(from_right: bool) -> void:
	light_from_right = from_right
	_update_light_masks()


func _update_light_masks() -> void:
	# 텍스처 공간에서의 빛 방향: 적은 좌우 반전되므로 뒤집는다.
	var tex_from_right := light_from_right
	if unit.team == "enemy":
		tex_from_right = not tex_from_right
	var suffix := "_mask_r" if tex_from_right else "_mask_l"
	var opposite := "_mask_l" if tex_from_right else "_mask_r"
	if rig != null:
		rig.set_light_direction(tex_from_right)   # 적은 좌우 반전 → 반전된 방향의 마스크
	else:
		mat.set_shader_parameter("zone_mask", load("res://assets/sprites/%s%s.png" % [unit.data.sprite_id, suffix]))
		mat.set_shader_parameter("near_rim_mask", load("res://assets/sprites/%s%s.png" % [unit.data.sprite_id, opposite]))
	if weapon.visible:
		var wid: String = unit.current_weapon().get("id", "")
		wmat.set_shader_parameter("zone_mask", load("res://assets/sprites/w_%s%s.png" % [wid, suffix]))
		wmat.set_shader_parameter("near_rim_mask", load("res://assets/sprites/w_%s%s.png" % [wid, opposite]))


## 장면 팔레트 공통 값 (셰이더 v7): 빛 없는 면은 주변광 색상으로, 형태 그림자면은 그림자 색상으로 물든다
func _apply_palette(m: ShaderMaterial, p: Dictionary) -> void:
	m.set_shader_parameter("shadow_tint", p.shadow)
	m.set_shader_parameter("ambient_tint", p.ambient)
	m.set_shader_parameter("palette_mix", float(p.get("char_palette_mix", 0.65)))
	m.set_shader_parameter("shadow_hue", 0.70)
	m.set_shader_parameter("shadow_depth", 0.80)
	m.set_shader_parameter("key_mix", float(p.get("char_light_mix", 0.85)))
	m.set_shader_parameter("use_rim", Game.rim_enabled)
	m.set_shader_parameter("debug_view", int(Game.cli.get("charview", "0")))
	# 얼굴은 원화색을 더 남겨 입술·피부·눈썹이 팔레트에 묻히지 않게
	# (빛 지도 모드는 몸 높이 띠로 이어지게 적용, 2D 배경 모드는 head 파츠만)
	m.set_shader_parameter("face_keep", 0.5 if (_lm_tex != null or _is_head_mat(m)) else 0.0)
	m.set_shader_parameter("face_band", _face_band)
	_apply_eye_paint(m)


func _is_head_mat(m: ShaderMaterial) -> bool:
	if rig == null:
		return false
	var i: int = rig.mats.find(m)
	return i >= 0 and rig.part_names[i] == "head"


## 2D 배경 모드 프리셋 적용. zone: "key" | "accent" | "ambient" — 유닛이 서 있는 빛 영역 (빛 지도 없음)
func apply_lighting(p: Dictionary, zone: String) -> void:
	ui_accent = p.get("ui_accent", ui_accent)
	for m in _all_mats():
		_apply_palette(m, p)
		m.set_shader_parameter("use_light_map", false)
		match zone:
			"accent":
				m.set_shader_parameter("key_color", p.accent)
				m.set_shader_parameter("accent_color", p.key)
			"ambient":
				m.set_shader_parameter("key_color", Color.BLACK)
				m.set_shader_parameter("accent_color", p.key)
			_:
				m.set_shader_parameter("key_color", p.key)
				m.set_shader_parameter("accent_color", p.accent)


## 3D 배경 모드: 3D 광원이 캐릭터 몸 위 어디에 닿는지 계산한 빛 지도로 명암을 정한다.
## 빛 지도는 발 기준 폭 lm_w × 높이 lm_h (m) 영역. from_right: 가장 센 빛이 오는 쪽 (형태 그림자 방향).
func apply_light_map(p: Dictionary, img: Image, from_right: bool, lm_w: float, lm_h: float) -> void:
	ui_accent = p.get("ui_accent", ui_accent)
	if _lm_tex == null or Vector2i(_lm_tex.get_size()) != img.get_size():
		_lm_tex = ImageTexture.create_from_image(img)
	else:
		_lm_tex.update(img)
	_lm_local = Rect2(-lm_w * 0.5 * PX_PER_M, -lm_h * PX_PER_M, lm_w * PX_PER_M, lm_h * PX_PER_M)
	_face_band = _face_band_for(lm_h)
	for m in _all_mats():
		_apply_palette(m, p)
		m.set_shader_parameter("use_light_map", true)
		m.set_shader_parameter("light_map", _lm_tex)
	_lm_xf = Transform2D(0.0, Vector2(-INF, -INF))
	_update_lm_rect()
	set_light_direction(from_right)


## 얼굴 보존 띠 (빛 지도 v 좌표): 턱 높이 위는 얼굴, 목까지 서서히 풀림. 리그의 head_rect 아래쪽 = 턱.
func _face_band_for(lm_h: float) -> Vector2:
	if rig == null or not rig.rig.has("head_rect") or not rig.rig.has("figure_px"):
		return Vector2(-1, -1)
	var hr: Array = rig.rig.head_rect
	var chin_up: float = (float(rig.rig.ground[1]) - (float(hr[1]) + float(hr[3]))) / float(rig.rig.figure_px)   # 키 대비 턱 높이
	var h_m := 1.75 * unit.data.height_cm / 175.0
	var v := 1.0 - chin_up * h_m / lm_h
	return Vector2(v - 0.01, v + 0.06)


## 빛 지도 영역을 캔버스 좌표로 (이동 트윈 중에도 따라가도록 매 프레임 확인)
func _update_lm_rect() -> void:
	var gt := get_global_transform()
	if gt.is_equal_approx(_lm_xf):
		return
	_lm_xf = gt
	var tl: Vector2 = gt * _lm_local.position
	var br: Vector2 = gt * _lm_local.end
	var r := Vector4(tl.x, tl.y, br.x - tl.x, br.y - tl.y)
	for m in _all_mats():
		m.set_shader_parameter("lm_rect", r)


## 로스터 eye_paint 가 있으면 눈동자를 그 색으로 진하게 칠하고, 없으면 원화 눈 색 그대로 둔다.
func _apply_eye_paint(m: ShaderMaterial) -> void:
	var pal: Dictionary = unit.data.palette
	m.set_shader_parameter("paint_eyes", pal.has("eye_paint"))
	m.set_shader_parameter("eye_color", Color(pal.get("eye_paint", pal.get("eyes", "#4f9cff"))))


func set_highlight(kind: String) -> void:
	highlight_kind = kind
	queue_redraw()


func _draw() -> void:
	# 바닥 접지 그림자 + 하이라이트 링 (UI 요소: 조명과 무관한 색)
	var r := Vector2(44, 13)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2.ONE)
	draw_ellipse_poly(Vector2.ZERO, r, Color(0, 0, 0, 0.35), true)
	match highlight_kind:
		"current":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), ui_accent, false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(ui_accent, 0.25), true)
		"target_ok":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1.0, 0.25, 0.2), false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1.0, 0.25, 0.2, 0.22), true)
		"target_ally":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.3, 1.0, 0.5), false, 4.0)
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.3, 1.0, 0.5, 0.22), true)
		"target_bad":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(0.5, 0.5, 0.5, 0.6), false, 2.0)
		"hover":
			draw_ellipse_poly(Vector2.ZERO, r + Vector2(10, 4), Color(1, 1, 1, 0.7), false, 2.0)


func draw_ellipse_poly(center: Vector2, radii: Vector2, color: Color, filled: bool, width: float = 1.0) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		pts.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		pts.append(pts[0])
		draw_polyline(pts, color, width, true)


func _process(delta: float) -> void:
	if _lm_tex != null:
		_update_lm_rect()
	if not unit.alive:
		return
	_bob_t += delta * (2.2 if highlight_kind == "current" else 1.4)
	var amp := 2.5 if highlight_kind == "current" else 1.5
	if rig == null:
		flip.position.y = sin(_bob_t + float(unit.instance_id)) * amp
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 4.0)
		for m in _all_mats():
			m.set_shader_parameter("flash_color", Color(1, 1, 1, _flash))


func head_screen_offset() -> Vector2:
	if rig != null:
		return Vector2(0, -rig_height - 6)
	var meta: Dictionary = manifest.units.get(unit.data.sprite_id, {})
	var h: float = float(meta.get("height", 460)) * BASE_SCALE
	return Vector2(0, -h - 6)


func _on_area_input(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(unit)
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- 연출
func play_attack(toward_right: bool, ranged: bool) -> Tween:
	if rig != null:
		rig.play("attack")
	var tw := create_tween()
	var dir := 1.0 if toward_right else -1.0
	if ranged:
		tw.tween_property(flip, "position:x", -10.0 * dir, 0.08).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(flip, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_BACK)
	else:
		tw.tween_property(flip, "position:x", 48.0 * dir, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(flip, "position:x", 0.0, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	return tw


func play_hit() -> void:
	_flash = 1.0
	if rig != null:
		rig.play("hit")
		return
	var tw := create_tween()
	tw.tween_property(flip, "rotation", -0.12 if unit.team == "ally" else 0.12, 0.06)
	tw.tween_property(flip, "rotation", 0.0, 0.16)


func play_heal() -> void:
	if rig != null:
		rig.play("heal")
		return
	var tw := create_tween()
	tw.tween_property(flip, "scale", flip.scale * 1.06, 0.12)
	tw.tween_property(flip, "scale", flip.scale, 0.18)


func play_death() -> void:
	if rig != null:
		rig.play("death")
		var tw2 := create_tween()
		tw2.tween_property(flip, "modulate", Color(0.55, 0.55, 0.6, 1.0), 0.8)   # 어둡게만, 투명하게 하지 않음
		z_index = 5
		set_highlight("none")
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(flip, "rotation", (-1.35 if unit.team == "ally" else 1.35), 0.45).set_trans(Tween.TRANS_BOUNCE)
	tw.tween_property(flip, "modulate", Color(0.55, 0.55, 0.6, 1.0), 0.6)
	z_index = 5
	set_highlight("none")
