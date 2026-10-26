class_name NpcView
extends Node2D
## 기지 대원 화면 노드: 전투와 같은 Skeleton2D 리그를, 3D 기지 위 그 대원의 발 위치(투영)에 원근 크기로, 지금 있는 방의 조명색으로.
## 머리 위: '!' 요청 마커, 수면 Zz, 마우스를 올리면 이름·상태. 화면 좌표 노드 (BaseHub 의 화면 층).

var npc_id: String = ""
var sim: BaseSim
var hub: Node               # BaseHub (투영)
var screen_h: float = 80.0  # 화면에서의 키 (px)
var _s: float = 0.4         # 리그 배율
var rig: RiggedUnit2D
var hovered: bool = false
var _anim := ""
var _light := ""
var _act_t := 0.0
var _font: Font
var _bold: Font


func setup(p_hub: Node, p_sim: BaseSim, id: String) -> void:
	hub = p_hub
	sim = p_sim
	npc_id = id
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var n: NpcAgent = sim.npcs[id]
	if UnitArt.has_rig(n.sprite):
		rig = RiggedUnit2D.new()
		add_child(rig)
		rig.build(UnitArt.rig_dir(n.sprite), false, n.height_cm)
		rig.set_param("eye_color", Color(0.3, 0.6, 1.0))
		rig.set_param("paint_eyes", false)
	_place(n)


## 3D 발 위치를 화면으로 투영, 1m 의 화면 길이로 크기 결정 (리그는 175cm = 230px 기준).
## 자세: 서기 / 앉기(골반을 의자 높이에) / 눕기(침대 위에 가로로). 계단을 오르내릴 때는 계단 깊이로.
var _z: float = 999.0
var _pose: String = "stand"


func _place(n: NpcAgent, delta: float = 1.0) -> void:
	var v3d: BaseView3D = hub.v3d
	var post: Dictionary = sim.posture(n)
	_pose = post.pose
	var want_z := v3d.stand_z(npc_id)
	var t := (n.pos.y + OutgameData.FLOOR_SLAB) / OutgameData.FLOOR_H
	var on_flight := absf(t - roundf(t)) > 0.01
	if on_flight:
		want_z = BaseView3D.flight_z(ceili(t) - 1)
	elif sim.data.facilities.get(n.facility, {}).get("tag", "") == "계단" and n.state == NpcAgent.MOVING:
		# 계단 방 안에서 계단 입구로 걸어갈 때 미리 계단 깊이로
		want_z = lerpf(want_z, BaseView3D.flight_z(int(sim.data.facilities[n.facility].order)), 0.7)
	if _pose != "stand":
		want_z = BaseView3D.SEAT_Z.get(post.kind, want_z)
	_z = want_z if _z > 900.0 else move_toward(_z, want_z, 2.5 * delta)
	var h_m := n.height_cm / 100.0
	var foot: Vector3 = v3d.to3d(n.pos, _z)
	var ppm: float = (hub.project(foot + Vector3.UP) - hub.project(foot)).length()
	_s = ppm * 1.75 / 230.0
	match _pose:
		"lie":
			# 침대 가운데에 등을 대고 가로로: 머리는 왼쪽(베개 쪽), 발 = 가운데 + 키/2 (회전 -90°)
			position = hub.project(foot + Vector3(h_m * 0.5, float(post.height) + 0.12, 0.0))
			screen_h = ppm * 0.6
		"sit":
			var hip := (rig.hip_ratio() if rig != null else 0.5) * h_m
			position = hub.project(foot + Vector3(0.0, float(post.height) + 0.05 - hip, 0.0))
			screen_h = ppm * (float(post.height) + h_m - hip)
		_:
			position = hub.project(foot)
			screen_h = ppm * h_m
	z_index = int((_z + 5.0) * 20.0)


func hit_rect() -> Rect2:
	if _pose == "lie":
		var len: float = screen_h / 0.6 * (sim.npcs[npc_id].height_cm / 100.0)
		return Rect2(position + Vector2(-len, -screen_h), Vector2(len, screen_h + 8))
	var w := maxf(22.0, screen_h * 0.42)
	return Rect2(position + Vector2(-w * 0.5, -screen_h - 6), Vector2(w, screen_h + 10))


func _process(delta: float) -> void:
	if sim == null:
		return
	var n: NpcAgent = sim.npcs.get(npc_id)
	if n == null:
		return
	visible = n.state != NpcAgent.UNAVAILABLE
	_place(n, delta)
	if rig != null:
		if _pose == "lie":
			rig.rotation = deg_to_rad(-90.0)
			rig.scale = Vector2(_s, _s)
		else:
			rig.rotation = 0.0
			rig.scale = Vector2(_s * n.facing, _s)
		_update_anim(n, delta)
		_update_light(n)
	queue_redraw()


func _update_anim(n: NpcAgent, delta: float) -> void:
	var want := "idle"
	if n.state == NpcAgent.MOVING:
		want = "walk"
	elif _pose == "sit":
		want = "sit"
	elif n.state in [NpcAgent.CLEANING, NpcAgent.TRAINING, NpcAgent.ASSIGNED_WORK, NpcAgent.TREATMENT]:
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
	var top := Vector2(0, -screen_h - 14)
	if _pose == "lie":
		top = Vector2(-hit_rect().size.x * 0.8, -screen_h * 1.2)
	elif _pose == "stand":
		# 발밑 그림자
		draw_set_transform(Vector2(0, 0), 0, Vector2(1, 0.3))
		draw_circle(Vector2.ZERO, screen_h * 0.24, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if not sim.active_request(npc_id).is_empty():
		var b := sin(Time.get_ticks_msec() / 180.0) * 3.0
		var c := top + Vector2(0, -12 + b)
		draw_circle(c, 15, Color(1, 0.85, 0.15))
		draw_circle(c, 15, Color(0.06, 0.05, 0.08), false, 3.0)
		_text(c + Vector2(0, 8), "!", 22, Color(0.06, 0.05, 0.08), _bold, false)
		top.y -= 30
	elif (n.activity == "sleep" and n.state == NpcAgent.STAYING) or n.state == NpcAgent.RECOVERING:
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
