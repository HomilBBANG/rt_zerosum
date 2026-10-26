class_name NpcView
extends Node2D
## 기지 대원 화면 노드: 전투와 같은 Skeleton2D 리그를 작게, 지금 있는 방의 조명색으로.
## 머리 위: '!' 요청 마커, 수면 Zz, 마우스를 올리면 이름·상태.

const BASE_SCALE := 0.5   # 전투 키(175cm = 230px) 대비 기지 크기

var npc_id: String = ""
var sim: BaseSim
var rig: RiggedUnit2D
var hovered: bool = false
var _anim := ""
var _light := ""
var _act_t := 0.0
var _font: Font
var _bold: Font


static func height_of(height_cm: float) -> float:
	return 230.0 * (height_cm / 175.0) * BASE_SCALE


func setup(p_sim: BaseSim, id: String) -> void:
	sim = p_sim
	npc_id = id
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var n: NpcAgent = sim.npcs[id]
	if UnitArt.has_rig(n.sprite):
		rig = RiggedUnit2D.new()
		add_child(rig)
		rig.build(UnitArt.rig_dir(n.sprite), false, n.height_cm)
		rig.scale = Vector2(BASE_SCALE, BASE_SCALE)
		rig.set_param("eye_color", Color(0.3, 0.6, 1.0))
		rig.set_param("paint_eyes", false)
	position = n.pos


func hit_rect() -> Rect2:
	var n: NpcAgent = sim.npcs[npc_id]
	var h := height_of(n.height_cm)
	return Rect2(n.pos + Vector2(-24, -h - 6), Vector2(48, h + 10))


func _process(delta: float) -> void:
	if sim == null:
		return
	var n: NpcAgent = sim.npcs.get(npc_id)
	if n == null:
		return
	visible = n.state != NpcAgent.UNAVAILABLE
	position = n.pos
	if rig != null:
		rig.scale.x = BASE_SCALE * n.facing
		_update_anim(n, delta)
		_update_light(n)
	queue_redraw()


func _update_anim(n: NpcAgent, delta: float) -> void:
	var want := "idle"
	if n.state == NpcAgent.MOVING:
		want = "walk"
	elif n.state in [NpcAgent.CLEANING, NpcAgent.TRAINING, NpcAgent.ASSIGNED_WORK]:
		want = "work"
	if want == "work":
		_act_t -= delta
		if _act_t <= 0.0:
			_act_t = 1.1 if n.state == NpcAgent.CLEANING else 1.6
			rig.anim.stop()
			rig.anim.play("attack" if n.state != NpcAgent.ASSIGNED_WORK else "heal")
		_anim = want
		return
	if want != _anim:
		_anim = want
		if rig.anim.has_animation(want):
			rig.anim.play(want)
		else:
			rig.anim.play("idle")


func _update_light(n: NpcAgent) -> void:
	var fid := n.facility
	var light: String = sim.data.facilities.get(fid, {}).get("light", "g1")
	if light == _light:
		return
	_light = light
	var p := LightingPresets.get_preset(light)
	rig.set_param("shadow_tint", p.shadow)
	rig.set_param("ambient_tint", p.ambient)
	rig.set_param("key_color", p.key)
	rig.set_param("accent_color", p.accent)
	rig.set_param("key_mix", p.char_key_mix)
	rig.set_param("accent_mix", p.char_accent_mix)


func _draw() -> void:
	var n: NpcAgent = sim.npcs.get(npc_id)
	if n == null:
		return
	var h := height_of(n.height_cm)
	var top := Vector2(0, -h - 14)
	# 발밑 그림자
	draw_set_transform(Vector2(0, 0), 0, Vector2(1, 0.25))
	draw_circle(Vector2.ZERO, 22, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if not sim.active_request(npc_id).is_empty():
		var b := sin(Time.get_ticks_msec() / 180.0) * 3.0
		var c := top + Vector2(0, -12 + b)
		draw_circle(c, 15, Color(1, 0.85, 0.15))
		draw_circle(c, 15, Color(0.06, 0.05, 0.08), false, 3.0)
		_text(c + Vector2(0, 8), "!", 22, Color(0.06, 0.05, 0.08), _bold, false)
		top.y -= 30
	elif n.activity == "sleep" and n.state == NpcAgent.STAYING:
		var t := Time.get_ticks_msec() / 600.0
		_text(top + Vector2(10, -4 - fmod(t, 1.0) * 10), "Z", 16, Color(0.8, 0.9, 1, 1.0 - fmod(t, 1.0) * 0.6), _bold, true)
	if hovered:
		var label := "%s · %s" % [n.name, n.state_name() if n.state != NpcAgent.STAYING else OutgameData.ACTIVITIES.get(n.activity, n.activity)]
		_text(top + Vector2(0, -8), label, 15, Color(1, 1, 1), _font, true)


func _text(pos: Vector2, s: String, size: int, col: Color, font: Font, outline: bool) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0)
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
