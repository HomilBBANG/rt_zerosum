class_name NpcView
extends Node2D
## 기지 대원 화면 노드: 전투와 같은 캐릭터 프레임 애니메이션(CharacterSprite2D)을, 3D 기지 위 그 대원의 발 위치(투영)에 원근 크기로.
## 조명은 방 프리셋 색이 아니라 **지금 자리에 실제로 닿는 스폿 조명**(BaseView3D.light_probe)으로 매 프레임: 빛 쪽·그림자 면·림이 걸어가는 동안 따라 바뀜 (부드럽게 섞음).
## 발밑 그림자 = 동그란 그림자 (3D 실루엣 그림자는 무거워서 2026-10-30 뺌). 누우면 없음.
## 머리 위: '!' 요청 마커, 수면 Zz, 마우스를 올리면 이름·상태. 화면 좌표 노드 (BaseHub 의 화면 층).

var npc_id: String = ""
var sim: BaseSim
var hub: Node               # BaseHub (투영)
var screen_h: float = 80.0  # 화면에서의 키 (px)
var _s: float = 0.4         # 캐릭터 배율
var chr: CharacterSprite2D
var hovered: bool = false
var selected: bool = false   # 플레이어가 고른 대원 (발밑 고리·이름·목적지 선)
var _anim := ""
var _light := ""
var _foot3 := Vector3.ZERO          # 이번 프레임 3D 발 위치 (조명 탐침 · 그림자 판)
var _lit := {"has": false, "color": Color.WHITE, "k": 0.0, "right": true, "behind": false, "rim": false, "rim_color": Color.WHITE, "rim_k": 0.0}
var _font: Font
var _bold: Font
const ALERT := preload("res://assets/ui/outgame/v2/alert.png")
var marker_at := Vector2.INF   # 머리 위 '!' 요청 마커 가운데 (이 노드 기준, 없으면 INF) — 누르면 요청 대화


func setup(p_hub: Node, p_sim: BaseSim, id: String) -> void:
	hub = p_hub
	sim = p_sim
	npc_id = id
	_font = load("res://assets/fonts/Pretendard-Medium.ttf")
	_bold = load("res://assets/fonts/Pretendard-Bold.ttf")
	var n: NpcAgent = sim.npcs[id]
	if CharacterSprite2D.exists(n.sprite):
		chr = CharacterSprite2D.new()
		add_child(chr)
		chr.build(n.sprite, n.height_cm)
		chr.set_param("eye_color", Color(0.3, 0.6, 1.0))
		chr.set_param("paint_eyes", false)
	_place(n)


## 3D 발 위치를 화면으로 투영, 1m 의 화면 길이로 크기 결정 (캐릭터는 175cm = 230px 기준).
## 자세: 서기 / 앉기(골반을 의자 높이에) / 눕기(침대 위에 가로로). 계단을 오르내릴 때는 계단 깊이로.
## 앉기·눕기 애니메이션(sit·sleep 프레임)이 없으면: 앉기 = 의자 앞에 서 있음, 눕기 = 기본 그림을 눕혀서.
var _z: float = 999.0
var _pose: String = "stand"


func _place(n: NpcAgent, delta: float = 1.0) -> void:
	var v3d: BaseView3D = hub.v3d
	var post: Dictionary = sim.posture(n)
	_pose = post.pose
	if _pose == "sit" and chr != null and not chr.has_anim("sit"):
		_pose = "stand"
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
	_foot3 = foot
	var ppm: float = (hub.project(foot + Vector3.UP) - hub.project(foot)).length()
	_s = ppm * 1.75 / 230.0
	match _pose:
		"lie":
			if chr != null and chr.has_anim("sleep"):
				# 누운 프레임: 접지점 = 침대에 닿는 몸 가운데
				position = hub.project(foot + Vector3(0.0, float(post.height), 0.0))
			else:
				# 기본 그림을 눕힘: 머리는 왼쪽(베개 쪽), 발 = 가운데 + 키/2 (회전 -90°)
				position = hub.project(foot + Vector3(h_m * 0.5, float(post.height) + 0.12, 0.0))
			screen_h = ppm * 0.6
		"sit":
			var hip := (chr.hip_ratio("sit") if chr != null else 0.5) * h_m
			position = hub.project(foot + Vector3(0.0, float(post.height) + 0.05 - hip, 0.0))
			screen_h = ppm * (float(post.height) + h_m - hip)
		_:
			position = hub.project(foot)
			screen_h = ppm * h_m
	z_index = int((_z + 5.0) * 20.0)


func hit_rect() -> Rect2:
	if _pose == "lie":
		var len: float = screen_h / 0.6 * (sim.npcs[npc_id].height_cm / 100.0)
		if chr != null and chr.has_anim("sleep"):
			return Rect2(position + Vector2(-len * 0.5, -screen_h), Vector2(len, screen_h + 8))
		return Rect2(position + Vector2(-len, -screen_h), Vector2(len, screen_h + 8))
	var w := maxf(22.0, screen_h * 0.42)
	return Rect2(position + Vector2(-w * 0.5, -screen_h - 6), Vector2(w, screen_h + 10))


## 그 점이 이 대원의 몸 위인가: 그림이 있으면 지금 프레임의 불투명 픽셀 (몸 어디든, 빈 곳은 안 잡힘), 없으면 사각형.
## 축소하면 대원이 작아져 팔다리 몇 px 만 남으므로: 몸통 기둥(머리~발, 키의 0.3배 폭, 최소 14px)도 잡고, 픽셀 여유도 작을수록 넓게
func hits(p: Vector2) -> bool:
	if chr == null or chr.body == null or chr.body.texture == null:
		return hit_rect().has_point(p)
	if _core_rect().has_point(p):
		return true
	if not chr.drawn_rect().grow(4.0).has_point(p):   # 그려진 그림 전체 (예전 사각형은 상반신을 놓침)
		return false
	return chr.hits(p, clampf(300.0 / maxf(1.0, screen_h), 3.0, 8.0))


## 몸통 기둥 (누우면 몸 전체 사각형)
func _core_rect() -> Rect2:
	var r := hit_rect()
	if _pose == "lie":
		return r
	var w := maxf(14.0, screen_h * 0.3)
	return Rect2(r.get_center().x - w * 0.5, r.position.y, w, r.size.y)


## 그 점이 머리 위 '!' 요청 마커 위인가
func marker_hits(p: Vector2) -> bool:
	return marker_at != Vector2.INF and visible and p.distance_to(position + marker_at) <= 20.0


func _process(delta: float) -> void:
	if sim == null:
		return
	var n: NpcAgent = sim.npcs.get(npc_id)
	if n == null:
		return
	visible = n.state != NpcAgent.UNAVAILABLE
	_place(n, delta)
	if chr != null:
		if _pose == "lie" and not chr.has_anim("sleep"):
			chr.rotation = deg_to_rad(-90.0)
			chr.scale = Vector2(_s, _s)
		else:
			chr.rotation = 0.0
			chr.scale = Vector2(_s * n.facing, _s)
		_update_anim(n)
		_update_light(n, delta)
	queue_redraw()


## 상태 → 애니메이션 (앞에서부터 프레임이 있는 것, 없으면 기본 그림)
func _update_anim(n: NpcAgent) -> void:
	var cands: Array = ["idle"]
	var paused: bool = hub.speed == 0 or hub.hud.modal_open() or not hub.sim.pending_battle.is_empty()   # 시계가 멈춤 = 걷던 대원도 멈춰 섬
	if n.state == NpcAgent.MOVING and paused:
		cands = ["idle"]
	elif n.state == NpcAgent.MOVING:
		cands = ["run", "walk", "idle"] if n.running else ["walk", "idle"]
	elif _pose == "lie":
		cands = ["sleep", "idle"]
	elif _pose == "sit":
		cands = ["sit", "idle"]
	elif n.state == NpcAgent.CLEANING:
		cands = ["clean", "work", "idle"]
	elif n.state == NpcAgent.TRAINING:
		cands = ["train", "work", "idle"]
	elif n.state in [NpcAgent.ASSIGNED_WORK, NpcAgent.TREATMENT]:
		cands = ["work", "idle"]
	elif n.state in [NpcAgent.CHATTING, NpcAgent.PLAYER_DIALOGUE]:
		cands = ["talk", "idle"]
	var want := chr.first_anim(cands)
	chr.speed_scale = 1.8 if (n.running and n.state == NpcAgent.MOVING and want == "walk") else 1.0   # 뛰기 시트가 없으면 걷기를 빠르게
	if want != _anim:
		_anim = want
		chr.play(want)


## 지금 자리에 닿는 스폿 조명으로 캐릭터 셰이더 갱신 (전투 UnitSprite2D.apply_light_probe 와 같은 규칙)
## 방 프리셋은 그림자·주변광 색만. 빛의 색·세기는 가장 센 조명, 반대쪽에서 오는 두 번째 조명은 림. 바뀔 때 0.25초쯤에 걸쳐 섞음.
func _update_light(n: NpcAgent, delta: float) -> void:
	var fid := n.facility
	var light: String = sim.data.facilities.get(fid, {}).get("light", "g1")
	var p := LightingPresets.get_preset(light)
	if light != _light:
		_light = light
		chr.set_param("shadow_tint", p.shadow)
		chr.set_param("ambient_tint", p.ambient)
	var h_m := n.height_cm / 100.0
	var probes: Array = hub.v3d.light_probe(_foot3, h_m)
	var key: Dictionary = probes[0] if not probes.is_empty() and float(probes[0].intensity) > 0.3 else {}
	var rim: Dictionary = {}
	if not key.is_empty():
		for pr in probes.slice(1):
			if pr.from_right != key.from_right and float(pr.intensity) > 0.3:
				rim = pr
				break
	var t := clampf(delta * 8.0, 0.0, 1.0)
	var ambient: Color = p.ambient
	if key.is_empty():
		_lit.color = (_lit.color as Color).lerp(ambient.lightened(0.5), t)
		_lit.k = lerpf(float(_lit.k), 0.0, t)
		_lit.has = float(_lit.k) > 0.02
	else:
		_lit.color = (_lit.color as Color).lerp(key.color, t)
		_lit.k = lerpf(float(_lit.k), clampf(float(key.intensity) / 3.0, 0.25, 1.0), t)
		_lit.has = true
		if absf(float(key.dx)) > 0.15:   # 바로 머리 위를 지날 때 좌우가 떨리지 않게
			_lit.right = key.from_right
		_lit.behind = bool(key.behind)
	# 림(빛 반대쪽 가장자리 선): 항상 켬. 반대쪽에서 실제로 오는 두 번째 빛이 있으면 그 색 · 세기,
	# 없으면 방 조명 프리셋의 림 색(accent · char_accent_mix) — 방이 하나의 조명이어도 윤곽이 보이게
	_lit.rim = Game.rim_enabled
	if _lit.rim:
		var rc: Color = rim.color if not rim.is_empty() else p.accent
		var rk: float = clampf(0.45 + float(rim.intensity) / 4.0, 0.45, 0.85) if not rim.is_empty() else float(p.get("char_accent_mix", 0.65))
		_lit.rim_color = (_lit.rim_color as Color).lerp(rc, t)
		_lit.rim_k = lerpf(float(_lit.rim_k), rk, t)
	var k := float(_lit.k)
	chr.set_param("key_color", _lit.color)
	chr.set_param("key_mix", lerpf(0.25, lerpf(0.45, 0.70, k), k) if _lit.has else 0.25)
	chr.set_param("shadow_depth", lerpf(0.86, 0.80, k))
	chr.set_param("shadow_hue", lerpf(0.30, 0.35, k))
	chr.set_param("use_near_rim", _lit.has and bool(_lit.behind) and Game.rim_enabled)
	chr.set_param("near_rim_color", _lit.color)
	chr.set_param("near_rim_mix", lerpf(0.7, 0.92, k))
	chr.set_param("use_rim", _lit.rim)
	if _lit.rim:
		chr.set_param("accent_color", _lit.rim_color)
		chr.set_param("accent_mix", float(_lit.rim_k))
	# 텍스처 기준 빛 방향: 왼쪽을 보면(가로 반전) 세계의 오른쪽 빛이 텍스처의 왼쪽에 닿음
	chr.set_light_direction(bool(_lit.right) if n.facing >= 0 else not bool(_lit.right))


func _draw() -> void:
	var n: NpcAgent = sim.npcs.get(npc_id)
	if n == null:
		return
	if _pose != "lie":   # 발밑 동그란 그림자 (앉으면 바닥의 발 자리)
		var foot: Vector2 = hub.project(_foot3) - position
		var rx := maxf(8.0, screen_h * 0.17)
		draw_set_transform(foot, 0.0, Vector2(1.0, 0.28))
		draw_circle(Vector2.ZERO, rx, Color(0, 0, 0, 0.4))
		draw_circle(Vector2.ZERO, rx * 0.62, Color(0, 0, 0, 0.16))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var top := Vector2(0, -screen_h - 14)
	if _pose == "lie":
		top = Vector2(-hit_rect().size.x * 0.8, -screen_h * 1.2)
	if selected:
		_draw_selected(n)
	marker_at = Vector2.INF
	if not sim.active_request(npc_id).is_empty():
		var b := sin(Time.get_ticks_msec() / 180.0) * 3.0
		var c := top + Vector2(0, -12 + b)
		marker_at = top + Vector2(0, -12)
		draw_texture_rect(ALERT, Rect2(c - Vector2(17, 17), Vector2(34, 34)), false)   # UI 패키지 v2 '!' 동그라미
		top.y -= 30
	elif not sim.pending_affinity_talk(npc_id).is_empty():   # 친밀도로 새 대화 해금 → 파스텔 노랑 하트
		var b2 := sin(Time.get_ticks_msec() / 220.0) * 3.0
		var hc := top + Vector2(0, -12 + b2)
		draw_circle(hc, 16, Color(0.06, 0.05, 0.08, 0.85))
		_heart(hc + Vector2(0, 1), 10.0, Color(1.0, 0.93, 0.6))
		top.y -= 30
	elif (n.activity == "sleep" and n.state == NpcAgent.STAYING) or n.state == NpcAgent.RECOVERING:
		var t := Time.get_ticks_msec() / 600.0
		_text(top + Vector2(10, -4 - fmod(t, 1.0) * 10), "Z", 16, Color(0.8, 0.9, 1, 1.0 - fmod(t, 1.0) * 0.6), _bold, true)
	if hovered or selected:
		var what: String = n.state_name() if n.state != NpcAgent.STAYING else OutgameData.ACTIVITIES.get(n.activity, n.activity)
		if n.state == NpcAgent.MOVING:
			what = "%s → %s" % ["뛰는 중" if n.running else "이동 중", sim.data.facility_name(n.dest)]
		var label := "%s · %s" % [n.name, what]
		_text(top + Vector2(0, -8), label, 15, Color(1, 1, 1), _font, true)


## 선택 표시: 발밑에 노란 고리(숨쉬듯 커졌다 작아짐), 이동 중이면 가는 방향 화살표
func _draw_selected(n: NpcAgent) -> void:
	var pulse := 1.0 + sin(Time.get_ticks_msec() / 260.0) * 0.06
	var r := maxf(18.0, screen_h * 0.3) * pulse
	var col := Color(1.0, 0.86, 0.25)
	draw_set_transform(Vector2(0, 2), 0.0, Vector2(1.0, 0.32))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0, 0, 0, 0.5), 6.0)
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, col, 3.0)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if n.state == NpcAgent.MOVING:
		var dir := float(n.facing)
		var base := Vector2(dir * (r + 6.0), 2.0)
		var tip := base + Vector2(dir * (14.0 if n.running else 9.0), 0.0)
		draw_colored_polygon(PackedVector2Array([tip, base + Vector2(0, -6), base + Vector2(0, 6)]), Color(1.0, 0.62, 0.2) if n.running else col)


func _heart(c: Vector2, r: float, col: Color) -> void:
	draw_circle(c + Vector2(-r * 0.48, -r * 0.3), r * 0.52, col)
	draw_circle(c + Vector2(r * 0.48, -r * 0.3), r * 0.52, col)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.98, -r * 0.12), c + Vector2(r * 0.98, -r * 0.12), c + Vector2(0, r * 0.95)]), col)


func _text(pos: Vector2, s: String, size: int, col: Color, font: Font, outline: bool) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos - Vector2(w * 0.5, 0)
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, 0.8))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
