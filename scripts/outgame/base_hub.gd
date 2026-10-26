extends Node2D
## 아웃게임 기지 화면 (scenes/outgame/base_hub.tscn).
## 배경 = 3D 단면 건물(BaseView3D, 위에서 살짝 내려다보는 원근 카메라) → 화면 뒤 층에 렌더.
## 그 위 화면 층: 방 이름표·자물쇠·오염(BaseOverlay under) → 대원 2D 리그(NpcView) → 말풍선(BaseOverlay over) → HUD.
## WASD 로 카메라 이동, 휠로 거리. 규칙은 Game.base(BaseSim). 클릭 우선순위 [임시]: UI > 말풍선 > 대원 > 시설.

const RENDER_SIZE := Vector2i(2560, 1440)   # QHD 로 렌더해 1280×720 논리 화면에 깐다
const SCREEN := Vector2(1280, 720)

@export_group("카메라")
@export_range(0.0, 60.0, 0.5, "suffix:°") var cam_pitch_deg := 15.0:   ## 내려다보는 각도 (0 = 정면)
	set(v):
		cam_pitch_deg = v
		_cam_dirty = true
@export_range(15.0, 70.0, 0.5, "suffix:°") var cam_fov_deg := 34.0:   ## 세로 화각
	set(v):
		cam_fov_deg = v
		_cam_dirty = true
@export_range(8.0, 80.0, 0.5, "suffix:m") var cam_distance := 36.0:   ## 바라보는 점까지 거리 (휠로 바뀜)
	set(v):
		cam_distance = v
		_cam_dirty = true
@export var cam_target := Vector3(12.6, -3.6, -0.6):   ## 바라보는 점 (m, WASD 로 바뀜)
	set(v):
		cam_target = v
		_cam_dirty = true
@export_range(1.0, 30.0, 0.5, "suffix:m/s") var cam_speed := 12.0   ## WASD 이동 속도 (거리 30m 기준)
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
var _hover_npc: String = ""
var _cam_dirty := true


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
	cam_target = Vector3(bb.get_center().x - 0.6, bb.get_center().y - 0.2, -0.6)
	if Game.cli.has("base_cam"):   # x,y,거리 (m)
		var p: PackedStringArray = str(Game.cli.base_cam).split(",")
		cam_target = Vector3(float(p[0]), float(p[1]), -0.6)
		if p.size() > 2:
			cam_distance = float(p[2])
	if sim.npcs.has(str(Game.cli.get("base_focus", ""))):
		var foot := v3d.to3d(sim.npcs[Game.cli.base_focus].pos)
		cam_target = Vector3(foot.x, foot.y + 1.2, -0.6)
		cam_distance = 14.0
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
	sim.day_changed.connect(func(_d): Game.save_campaign())
	sim.room_unlocked.connect(func(fid): v3d.rebuild_room(fid); _rerender())
	Game.outgame_reloaded.connect(_on_reloaded)
	hud.refresh_log()
	if Game.cli.has("base_skip"):
		sim.skip(int(Game.cli.base_skip))
	if Game.cli.has("base_ui"):
		call_deferred("_cli_ui", str(Game.cli.base_ui))
	Game.maybe_cli_capture(30)


func _make_3d() -> void:
	vp = SubViewport.new()
	vp.name = "Base3D"
	vp.size = RENDER_SIZE
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.positional_shadow_atlas_size = 4096
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
	v3d.set_camera(cam_target, cam_distance, cam_pitch_deg, cam_fov_deg)
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
	if not hud.modal_open() and speed > 0:
		sim.advance(delta * sim.data.num("minutes_per_second", 1.0) * speed)
	_update_hover()
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
	if dir != Vector2.ZERO:
		var k := cam_speed * delta * cam_distance / 30.0
		var bb := v3d.base_bounds().grow(4.0)
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
	Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if (n != "" or _bubble_at(p) != "" or _pick_npc != "") else Input.CURSOR_ARROW)


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
				get_viewport().set_input_as_handled()
			KEY_F1:
				hud.toggle_debug()
			KEY_SPACE:
				speed = 1 if speed == 0 else 0
	if hud.modal_open():
		return
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom(1.1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom(1.0 / 1.1)
			MOUSE_BUTTON_LEFT:
				_left_click(_world_mouse())
			MOUSE_BUTTON_RIGHT:
				_right_click(_world_mouse(), event.position)


func _zoom(k: float) -> void:
	cam_distance = clampf(cam_distance / k, 8.0, 48.0)


func _left_click(p: Vector2) -> void:
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
	if n != "":
		hud.open_dialogue(n)
		return
	var fid := under.facility_at_screen(p)
	if fid == "":
		return
	if sim.is_unlocked(fid):
		hud.open_facility(fid)
	else:
		hud.open_unlock(fid)


func _right_click(p: Vector2, screen: Vector2) -> void:
	if _pick_npc != "":
		_end_pick()
		return
	var n := _npc_at(p)
	if n != "":
		hud.open_context(n, screen)   # 내장 팝업 위치 = 논리 화면 좌표


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
		"unlock": hud.open_unlock(p[1])
		"facility": hud.open_facility(p[1])
		"character": hud.open_character(p[1])
		"contracts": hud.open_contracts("")
		"statement":
			if not sim.ledger.statements.is_empty():
				hud.open_statement(sim.ledger.statements[-1])
		"inspection":
			sim.debug_inspect_now()
		"context":
			var v: NpcView = npc_views[p[1]]
			v._place(sim.npcs[p[1]])   # 시간 건너뛴 직후라 화면 위치 갱신
			hud.open_context(p[1], v.position + Vector2(20, -40))
		"clean":
			begin_clean_pick(p[1])
		"debug":
			hud.toggle_debug()
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
