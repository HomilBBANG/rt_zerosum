extends Node2D
## 아웃게임 기지 화면 (scenes/outgame/base_hub.tscn).
## 배경 = 3D 단면 건물(BaseView3D) → 화면 뒤 층에 렌더. 카메라는 직교(정면처럼 반듯, 방마다 같은 크기 사각형) + 살짝 내려다봐 방 안 바닥이 보임.
## 그 위 화면 층: 방 이름표·자물쇠·오염(BaseOverlay under) → 대원 2D 리그(NpcView) → 말풍선(BaseOverlay over) → HUD.
## WASD 로 카메라 이동, 휠로 거리. 규칙은 Game.base(BaseSim). 클릭 우선순위 [임시]: UI > 말풍선 > 대원 > 시설.

const RENDER_SIZE := Vector2i(2560, 1440)   # QHD 로 렌더해 1280×720 논리 화면에 깐다
const SCREEN := Vector2(1280, 720)
## 확대 한계 (화면 세로에 들어가는 높이, m). 3D 배경은 늘 QHD 로 다시 그려 어느 배율에서도 선명하므로, 한계는 대원 원화 해상도:
## 원화 전신 ≈ 760px, 가장 큰 대원 1.85m 가 QHD 세로 1440px 화면에서 원화보다 커지지 않는 값 = 1.85 × 1440 / 760 ≈ 3.5 → 3.6.
## 축소 한계는 기지 전체(가로 9칸 32.4m → 16:9 세로 18.2m)가 여유 있게 들어오는 20m.
const ZOOM_MIN := 3.6
const ZOOM_MAX := 20.0
const ZOOM_DEFAULT := 9.0

@export_group("카메라")
@export_range(0.0, 45.0, 0.5, "suffix:°") var cam_pitch_deg := 18.0:   ## 방 안을 내려다보는 각도 (0 = 완전 정면, 바닥 안 보임). 18° 에서 한 칸이 정사각형
	set(v):
		cam_pitch_deg = v
		_cam_dirty = true
@export_range(3.6, 20.0, 0.1, "suffix:m") var cam_size := 9.0:   ## 화면 세로에 들어가는 높이 (작을수록 확대, 휠·핀치·Q/E 로 바뀜). 9 ≈ 두 층 반
	set(v):
		cam_size = v
		_cam_dirty = true
@export var cam_target := Vector3(12.6, -3.6, -0.6):   ## 바라보는 점 (m, WASD 로 바뀜)
	set(v):
		cam_target = v
		_cam_dirty = true
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var cam_speed := 9.0   ## WASD 이동 속도 (화면 높이 8m 기준)
@export_group("")

var sim: BaseSim
var v3d: BaseView3D
var vp: SubViewport
var under: BaseOverlay
var over: BaseOverlay
var screen_root: Node2D
var npc_views: Dictionary = {}     # npc id → NpcView
var hud: OutgameHud
var speed: int = 1                 # 0 = 정지, 1 / 4 / 16 배
var _pick_npc: String = ""         # 청소 장소 고르는 중인 대원
var selected: String = ""          # 선택한 대원 (클릭) — 방 클릭 = 그 방으로 이동, 더블클릭 = 뛰어감, 도착 후 우클릭 = 행동
var move_mark: Dictionary = {}     # 이동 목표 표시 {pos(화면), t, run}
var _hover_npc: String = ""
var _cam_dirty := true
var _zoom_goal := ZOOM_DEFAULT      # 부드럽게 따라가는 목표 확대
var _zoom_anchor := SCREEN * 0.5    # 확대해도 제자리에 남는 화면 점 (마우스 위치)


func _ready() -> void:
	if Game.base == null:
		Game.start_base_session()
	sim = Game.base
	if sim == null:
		push_error("기지 데이터(data/outgame.xlsx)를 읽지 못했습니다")
		return
	RenderingServer.set_default_clear_color(Color(0.1, 0.06, 0.08))
	_make_3d()
	var bb := v3d.base_bounds()
	# 처음엔 지상 1층·지하 1층 가운데(대원들이 있는 곳)를 크게
	var start := v3d.to3d(Vector2(sim.data.facility_center_x("f1_lounge") if sim.data.facilities.has("f1_lounge") else bb.get_center().x / BaseView3D.CELL_M * OutgameData.CELL_W, OutgameData.FLOOR_H))
	cam_target = Vector3(start.x - BaseView3D.CELL_M * 0.5, start.y + 0.3, -0.6)
	if Game.cli.has("base_cam"):   # x,y,화면 높이 (m)
		var p: PackedStringArray = str(Game.cli.base_cam).split(",")
		cam_target = Vector3(float(p[0]), float(p[1]), -0.6)
		if p.size() > 2:
			cam_size = float(p[2])
	if sim.npcs.has(str(Game.cli.get("base_focus", ""))):
		var foot := v3d.to3d(sim.npcs[Game.cli.base_focus].pos)
		cam_target = Vector3(foot.x, foot.y + float(Game.cli.get("base_focus_y", 1.2)), -0.6)
		cam_size = float(Game.cli.get("base_zoom", 5.0))   # 화면 높이 (m) — 작을수록 가까이
	cam_size = clampf(cam_size, ZOOM_MIN, ZOOM_MAX)
	_zoom_goal = cam_size
	_apply_camera()
	var layer := CanvasLayer.new()
	layer.layer = 0
	add_child(layer)
	screen_root = Node2D.new()
	layer.add_child(screen_root)
	under = BaseOverlay.new()
	under.sim = sim
	under.v3d = v3d
	under.hub = self
	screen_root.add_child(under)
	for id in sim.data.npc_order:
		_add_npc_view(id)
	over = BaseOverlay.new()
	over.mode = "over"
	over.sim = sim
	over.v3d = v3d
	over.hub = self
	over.z_index = 400
	screen_root.add_child(over)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = OutgameHud.new()
	hud_layer.add_child(hud)
	hud.setup(self, sim)
	sim.notice.connect(_on_notice)
	sim.statement_ready.connect(func(st): hud.enqueue(func(): hud.open_statement(st)))
	sim.inspection_completed.connect(func(rec): hud.enqueue(func(): hud.open_inspection(rec)))
	sim.leveled_up.connect(func(cid, lv): hud.show_toast("%s 레벨 업! Lv%d — 스킬 포인트 +1" % [sim._char_label(cid), lv], OutgameHud.GOOD))
	sim.research_completed.connect(func(qid): hud.show_toast("연구 완료: %s — 무기고에서 제작 가능" % sim.data.research.get(qid, {}).get("name", qid), OutgameHud.GOOD))
	sim.day_changed.connect(func(_d): Game.save_campaign())
	sim.room_unlocked.connect(func(fid): v3d.rebuild_room(fid); _rerender())
	Game.outgame_reloaded.connect(_on_reloaded)
	hud.refresh_log()
	if Game.cli.has("base_skip"):
		sim.skip(int(Game.cli.base_skip))
	if Game.cli.has("base_battle_soon"):
		var nb := sim.next_battle()
		if not nb.is_empty():
			sim.skip(maxi(0, int(nb.minute) - sim.clock.minute_int() - 10))
	if Game.cli.has("base_ui"):
		for spec in str(Game.cli.base_ui).split(";"):   # 여러 개는 ; 로 (순서대로)
			call_deferred("_cli_ui", spec)
	Game.maybe_cli_capture(30)


func _make_3d() -> void:
	vp = SubViewport.new()
	vp.name = "Base3D"
	vp.size = RENDER_SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.positional_shadow_atlas_size = 8192   # 방 스폿 조명마다 2048² (가까이 봐도 그림자 경계가 깔끔하게)
	for q in 4:
		vp.set_positional_shadow_atlas_quadrant_subdiv(q, Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_4)
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	v3d = BaseView3D.new()
	vp.add_child(v3d)
	v3d.build(sim)
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var tr := TextureRect.new()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.texture = vp.get_texture()
	tr.position = Vector2.ZERO
	tr.size = SCREEN
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)


## 3D 위치 → 논리 화면 좌표 (1280×720)
func project(p: Vector3) -> Vector2:
	return v3d.camera.unproject_position(p) * (SCREEN.x / float(RENDER_SIZE.x))


func _apply_camera() -> void:
	if v3d == null:
		return
	v3d.set_camera(cam_target, cam_size, cam_pitch_deg)
	_cam_dirty = false
	_rerender()


func _rerender() -> void:
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_rerender_next.call_deferred()


## 그림자 지도 갱신이 한 프레임 늦을 수 있어 다음 프레임에 한 번 더
func _rerender_next() -> void:
	await get_tree().process_frame
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _add_npc_view(id: String) -> void:
	if npc_views.has(id) or not sim.npcs.has(id):
		return
	var v := NpcView.new()
	screen_root.add_child(v)
	v.setup(self, sim, id)
	npc_views[id] = v


func _on_reloaded(_w: PackedStringArray) -> void:
	sim = Game.base
	for id in sim.data.npc_order:
		_add_npc_view(id)
	for fid in sim.data.facility_order:
		v3d.rebuild_room(fid)
	_rerender()
	hud.show_toast("기지 데이터(엑셀·일정) 다시 읽음")


func _on_notice(text: String) -> void:
	hud.refresh_log()
	hud.show_toast(text)


# ================================================================ 진행
func set_speed(v: int) -> void:
	speed = v


func _process(delta: float) -> void:
	if sim == null:
		return
	_move_camera(delta)
	# 창이 열려 있거나 전투가 발생해 대기 중이면 기지 시계 정지
	if not hud.modal_open() and speed > 0 and sim.pending_battle.is_empty():
		sim.advance(delta * sim.data.num("minutes_per_second", 1.0) * speed)
	_update_hover()
	if not move_mark.is_empty():
		move_mark.t = float(move_mark.t) + delta
		if float(move_mark.t) > 0.9:
			move_mark = {}
		under.move_mark = move_mark
		under.queue_redraw()
	if selected != "" and not sim.npcs.has(selected):
		select("")
	hud.refresh(delta)


func _move_camera(delta: float) -> void:
	var dir := Vector2.ZERO
	if not hud.modal_open():
		if Input.is_physical_key_pressed(KEY_A):
			dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D):
			dir.x += 1
		if Input.is_physical_key_pressed(KEY_W):
			dir.y += 1
		if Input.is_physical_key_pressed(KEY_S):
			dir.y -= 1
		# Q / E 누르고 있으면 계속 축소 / 확대 (화면 가운데 기준)
		if Input.is_physical_key_pressed(KEY_E):
			_zoom(exp(1.6 * delta), SCREEN * 0.5)
		if Input.is_physical_key_pressed(KEY_Q):
			_zoom(exp(-1.6 * delta), SCREEN * 0.5)
	_update_zoom(delta)
	if dir != Vector2.ZERO:
		var k := cam_speed * delta * cam_size / 8.0
		var bb := v3d.base_bounds()
		var t := cam_target + Vector3(dir.x, dir.y, 0.0) * k
		cam_target = Vector3(clampf(t.x, bb.position.x, bb.end.x), clampf(t.y, bb.position.y, bb.end.y), t.z)
	if _cam_dirty:
		_apply_camera()


# ================================================================ 마우스
## 마우스 위치 (논리 화면 좌표 — 대원·덮개와 같은 공간)
func _world_mouse() -> Vector2:
	return get_viewport().get_mouse_position()


func _npc_at(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for id in npc_views:
		var v: NpcView = npc_views[id]
		if not v.visible:
			continue
		var r := v.hit_rect()
		if r.has_point(p):
			var d := absf(r.get_center().x - p.x)
			if d < best_d:
				best = id
				best_d = d
	return best


func _bubble_at(p: Vector2) -> String:
	for key in over.bubble_rects:
		if (over.bubble_rects[key] as Rect2).grow(6).has_point(p):
			return key
	return ""


func _update_hover() -> void:
	if hud.modal_open():
		return
	var p := _world_mouse()
	var n := "" if _bubble_at(p) != "" else _npc_at(p)
	if n != _hover_npc:
		if npc_views.has(_hover_npc):
			npc_views[_hover_npc].hovered = false
		_hover_npc = n
		if npc_views.has(n):
			npc_views[n].hovered = true
	under.hover_fid = "" if n != "" else under.facility_at_screen(p)
	var go := selected != "" and under.hover_fid != ""
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if (n != "" or _bubble_at(p) != "" or _pick_npc != "" or go) else Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	if sim == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				if _pick_npc != "":
					_end_pick()
				elif hud.modal_open():
					hud.close_top()
				elif selected != "":
					select("")
				get_viewport().set_input_as_handled()
				return
			KEY_TAB:   # 다음 대원 선택
				var ids: Array = sim.data.npc_order
				if not ids.is_empty():
					select(ids[(ids.find(selected) + 1) % ids.size()])
				get_viewport().set_input_as_handled()
			KEY_F1:
				hud.toggle_debug()
			KEY_SPACE:
				speed = 1 if speed == 0 else 0
			KEY_EQUAL, KEY_KP_ADD:
				zoom_step(1)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_step(-1)
			KEY_0, KEY_KP_0:
				_zoom_goal = ZOOM_DEFAULT
				_zoom_anchor = SCREEN * 0.5
	if hud.modal_open():
		return
	# Mac 트랙패드: 핀치 = 확대/축소, 두 손가락 위아래 = 휠과 같음
	if event is InputEventMagnifyGesture:
		_zoom(event.factor, event.position)
		return
	if event is InputEventPanGesture:
		_zoom(pow(1.06, -event.delta.y), event.position)
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.15 * maxf(1.0, event.factor), event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / (1.15 * maxf(1.0, event.factor)), event.position)
			MOUSE_BUTTON_LEFT:
				_left_click(_world_mouse(), event.double_click)
			MOUSE_BUTTON_RIGHT:
				_right_click(_world_mouse(), event.position)


## k > 1 = 확대. anchor = 확대해도 그대로 남을 화면 점 (마우스 위치)
func _zoom(k: float, anchor: Vector2 = SCREEN * 0.5) -> void:
	_zoom_goal = clampf(_zoom_goal / k, ZOOM_MIN, ZOOM_MAX)
	_zoom_anchor = anchor


## HUD 버튼·+/- 키: 한 단계 확대(+1)/축소(-1)
func zoom_step(dir: int) -> void:
	_zoom(1.25 if dir > 0 else 1.0 / 1.25, SCREEN * 0.5)


## 기본(9m) 대비 확대 %
func zoom_percent() -> int:
	return roundi(ZOOM_DEFAULT / _zoom_goal * 100.0)


## 확대 목표로 부드럽게 다가가며, 기준점(마우스 아래 지점)이 화면에서 움직이지 않게 카메라를 옮긴다
func _update_zoom(delta: float) -> void:
	if is_equal_approx(cam_size, _zoom_goal):
		return
	var nz := lerpf(cam_size, _zoom_goal, 1.0 - exp(-14.0 * delta))
	if absf(nz - _zoom_goal) < 0.005:
		nz = _zoom_goal
	var d := _zoom_anchor - SCREEN * 0.5
	var ds := (cam_size - nz) / SCREEN.y   # 화면 1px 당 m 변화
	var bb := v3d.base_bounds()
	var t := cam_target + Vector3(d.x * ds, -d.y * ds / cos(deg_to_rad(cam_pitch_deg)), 0.0)
	cam_target = Vector3(clampf(t.x, bb.position.x, bb.end.x), clampf(t.y, bb.position.y, bb.end.y), t.z)
	cam_size = nz


## 왼쪽 클릭: 대원 = 선택 (선택한 대원을 한 번 더 = 대화) / 선택한 대원이 있으면 방 = 그 위치로 걸어감, 더블클릭 = 뛰어감 /
## 선택 없으면 방 = 시설 창(잠긴 방 = 해금). 빈 곳 = 선택 해제
func _left_click(p: Vector2, dbl: bool = false) -> void:
	if _pick_npc != "":
		var fid := under.facility_at_screen(p)
		var r := sim.issue_clean(_pick_npc, fid)
		hud.show_toast(r.msg, OutgameHud.GOOD if r.ok else OutgameHud.BAD)
		if r.ok or fid == "":
			_end_pick()
		return
	var key := _bubble_at(p)
	if key != "":
		hud.open_overhear(key)
		return
	var n := _npc_at(p)
	if n != "" and sim.is_researcher(n) and not dbl:   # 연구원(로한) 클릭 = 무기 연구 창
		hud.open_research()
		return
	if n != "" and not (dbl and selected != "" and n != selected):
		if n == selected and not dbl:
			hud.open_dialogue(n)
		else:
			select(n)
		return
	var fid := under.facility_at_screen(p)
	if selected == "":
		if fid == "":
			return
		if sim.is_unlocked(fid):
			hud.open_facility(fid)
		else:
			hud.open_unlock(fid)
		return
	if fid == "":
		select("")
		return
	if not sim.is_unlocked(fid):
		hud.open_unlock(fid)
		return
	var r2 := sim.issue_move(selected, fid, room_x_at(fid, p), dbl)
	if not r2.ok:
		hud.show_toast(r2.msg, OutgameHud.BAD)
		return
	move_mark = {"pos": p, "t": 0.0, "run": dbl, "fid": fid}


## 화면 점 → 그 방 안의 규칙 좌표 x (방 앞면 사각형에서의 가로 비율)
func room_x_at(fid: String, p: Vector2) -> float:
	var q := under.front_quad(fid)
	var r := sim.data.facility_rect(fid)
	var t := clampf((p.x - q[0].x) / maxf(1.0, q[1].x - q[0].x), 0.0, 1.0)
	return r.position.x + t * r.size.x


## 오른쪽 클릭: 대원 = 그 대원 선택 + 행동 메뉴 / 선택한 대원이 있는 방 = 그 방에서 할 행동 메뉴
func _right_click(p: Vector2, screen: Vector2) -> void:
	if _pick_npc != "":
		_end_pick()
		return
	var n := _npc_at(p)
	if n != "":
		select(n)
		hud.open_context(n, screen)   # 내장 팝업 위치 = 논리 화면 좌표
		return
	if selected == "":
		return
	var fid := under.facility_at_screen(p)
	var sn: NpcAgent = sim.npcs[selected]
	if fid == "":
		select("")
	elif sn.facility == fid and sn.state != NpcAgent.MOVING:
		hud.open_context(selected, screen)
	elif sn.state == NpcAgent.MOVING and sn.dest == fid:
		hud.show_toast("%s 이(가) 아직 %s 로 가는 중입니다 — 도착하면 우클릭" % [sn.name, sim.data.facility_name(fid)], OutgameHud.BAD)
	else:
		hud.show_toast("%s 은(는) %s 에 없습니다 — 왼쪽 클릭으로 먼저 보내세요" % [sn.name, sim.data.facility_name(fid)], OutgameHud.BAD)


func select(npc_id: String) -> void:
	if npc_views.has(selected):
		npc_views[selected].selected = false
	selected = npc_id if sim.npcs.has(npc_id) else ""
	if npc_views.has(selected):
		npc_views[selected].selected = true
	hud.show_selection(selected)


func begin_clean_pick(npc_id: String) -> void:
	_pick_npc = npc_id
	under.pick_mode = true
	hud.set_banner("%s: 청소할 장소를 클릭하세요 (우클릭·Esc 취소)" % sim.data.npc_name(npc_id))


func _end_pick() -> void:
	_pick_npc = ""
	under.pick_mode = false
	hud.set_banner("")


# ================================================================ 버튼 동작
func save_now() -> void:
	var ok := Game.save_campaign()
	hud.show_toast("저장했습니다" if ok else "저장 실패", OutgameHud.GOOD if ok else OutgameHud.BAD)


func to_title() -> void:
	Game.save_campaign()
	Game.go_title()


func sortie(stage: String) -> void:
	hud.close_all()
	Game.sortie(stage)


func debug_skip(minutes: int) -> void:
	match minutes:
		-1: sim.skip_to_next_day()
		-7: sim.skip_to_next_week()
		-30: sim.skip_to_next_month()
		_: sim.skip(minutes)
	hud.refresh_log()


func debug_battle() -> void:
	sim.debug_trigger_battle()


func debug_dirt() -> void:
	var cands := sim.data.facility_order.filter(func(f): return sim.is_unlocked(f) and sim.cleanable(f))
	if not cands.is_empty():
		sim.add_dirt(cands[randi() % cands.size()])


func debug_delete_save() -> void:
	Game.delete_save()
	hud.show_toast("저장 파일 삭제 (지금 진행은 그대로)")


## CLI 스크린샷용: --base_ui=dialogue:npc_alma | overhear | unlock:f1_mess | facility:b1_workshop | context:npc_dan | statement | character:npc_kira
func _cli_ui(spec: String) -> void:
	var p := spec.split(":")
	match p[0]:
		"dialogue": hud.open_dialogue(p[1])
		"overhear":
			if not sim.chats.is_empty():
				hud.open_overhear(sim.chats[0].key)
		"facility": hud.open_facility(p[1])
		"skills":   # skills[:캐릭터 id[:경험치[:배울 노드,노드…[:고를 노드[:active|passive|faith]]]]] — 스킬 창 (경험치 주고 배우기)
			var cid := p[1] if p.size() > 1 else ""
			if p.size() > 2 and cid != "":
				sim.add_xp(cid, int(p[2]))
			if p.size() > 3 and cid != "":
				for nid in p[3].split(",", false):
					sim.learn_skill(cid, nid)
			hud.open_skills(cid, p[4] if p.size() > 4 else "", p[5] if p.size() > 5 else "active")
		"faith":   # faith:캐릭터 id[:더할 신앙도[:배울 신앙 스킬,…]] — 스킬 창 신앙 탭
			var fc := p[1]
			if p.size() > 2:
				sim.add_faith(fc, int(p[2]))
			if p.size() > 3:
				for sid in p[3].split(",", false):
					sim.learn_faith_skill(fc, sid)
			hud.open_skills(fc, "", "faith")
		"research":   # research[:연구 id[:건너뛸 분]] — 연구 창 (연구 시작 + 시간 건너뛰기)
			if p.size() > 1:
				sim.ledger.cash = maxi(sim.ledger.cash, 500)
				sim.start_research(p[1])
				if p.size() > 2:
					sim.skip(int(p[2]))
			hud.open_research()
		"character": hud.open_character(p[1])
		"contracts": hud.open_contracts("")
		"statement":
			if not sim.ledger.statements.is_empty():
				hud.open_statement(sim.ledger.statements[-1])
		"inspection":
			sim.debug_inspect_now()
		"select":   # select:npc_dan
			select(p[1])
		"move":   # move:npc_dan:b1_quarters[:run[:skip분]] — 선택 + 이동 (+ 시간 건너뛰기)
			select(p[1])
			var r := sim.issue_move(p[1], p[2], NAN, p.size() > 3 and p[3] == "run")
			hud.show_toast(r.msg, OutgameHud.GOOD if r.ok else OutgameHud.BAD)
			if p.size() > 4:
				sim.skip(int(p[4]))
		"act":   # act:npc_dan:sleep — 지금 방에서 행동
			var r2 := sim.issue_activity(p[1], p[2])
			hud.show_toast(r2.msg, OutgameHud.GOOD if r2.ok else OutgameHud.BAD)
		"context":
			var v: NpcView = npc_views[p[1]]
			v._place(sim.npcs[p[1]])   # 시간 건너뛴 직후라 화면 위치 갱신
			hud.open_context(p[1], v.position + Vector2(20, -40))
		"clean":
			begin_clean_pick(p[1])
		"debug":
			hud.toggle_debug()
		"battle_event":
			sim.debug_trigger_battle()
		"medical":   # 단을 다치게 하고 의무실로
			sim.apply_battle_result({"winner": "ally", "allies": [{"id": "a_dan", "hp": 0, "alive": false, "statuses": []}, {"id": "a_kira", "hp": 12, "alive": true, "statuses": []}]})
			sim.issue_medical("npc_dan")
			sim.issue_medical("npc_kira")
			sim.skip(30)
		"affinity":   # PX 해금·선물 구매 → 단에게 장갑 (친밀도 30 대화 해금 ♥). affinity:talk = 대화창까지
			sim.ledger.cash += 300
			sim.try_unlock("f1_px")
			for g in ["gift_gloves", "gift_coffee", "gift_choco", "gift_book"]:
				sim.buy_gift(g)
			sim.give_gift("npc_dan", "gift_gloves")
			if p.size() > 1 and p[1] == "talk":
				hud.open_dialogue("npc_dan")
		"unlock":
			hud.open_unlock(p[1])
		"unlockall":   # 모든 시설 해금 (3D 내부 확인용)
			sim.ledger.cash += 10000
			for fid in sim.data.facility_order:
				sim.try_unlock(fid)
		"sortie":
			hud.open_sortie()
		"sortie_go":   # 기지 → 전투 배치 (편성) 바로
			sortie(Game.data.stage_order[0])
		"battle_go":   # 기지 → 전투 바로 (훈련 1단계 반영 확인용)
			sim.progression["a_dan"] = {"training": 2}
			Game.sortie(Game.data.stage_order[0])
			Game.start_battle.call_deferred()
