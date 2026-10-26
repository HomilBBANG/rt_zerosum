extends Node2D
## 아웃게임 기지 화면 (scenes/outgame/base_hub.tscn).
## 기지 단면을 WASD 로 둘러보고, 대원·말풍선·방을 클릭한다. 규칙은 Game.base(BaseSim), 그리기는 BaseWorldView·NpcView, UI 는 OutgameHud.
## 클릭 우선순위 [임시]: UI > 말풍선 > 대원 > 시설.

const CAM_SPEED := 900.0
const ZOOM_MIN := 0.42
const ZOOM_MAX := 1.6

var sim: BaseSim
var world: BaseWorldView
var npc_views: Dictionary = {}     # npc id → NpcView
var cam: Camera2D
var hud: OutgameHud
var speed: int = 1                 # 0 = 정지, 1 / 4 / 16 배
var _pick_npc: String = ""         # 청소 장소 고르는 중인 대원
var _hover_npc: String = ""


func _ready() -> void:
	if Game.base == null:
		Game.start_base_session()
	sim = Game.base
	if sim == null:
		push_error("기지 데이터(data/outgame.xlsx)를 읽지 못했습니다")
		return
	RenderingServer.set_default_clear_color(Color(0.1, 0.06, 0.08))
	world = BaseWorldView.new()
	world.sim = sim
	add_child(world)
	for id in sim.data.npc_order:
		_add_npc_view(id)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	var br := sim.data.base_rect()
	cam.position = Vector2(br.get_center().x, br.get_center().y + 40)
	cam.zoom = Vector2(0.56, 0.56)
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = OutgameHud.new()
	layer.add_child(hud)
	hud.setup(self, sim)
	sim.notice.connect(_on_notice)
	sim.statement_ready.connect(func(st): hud.enqueue(func(): hud.open_statement(st)))
	sim.inspection_completed.connect(func(rec): hud.enqueue(func(): hud.open_inspection(rec)))
	sim.day_changed.connect(func(_d): Game.save_campaign())
	Game.outgame_reloaded.connect(_on_reloaded)
	hud.refresh_log()
	if Game.cli.has("base_cam"):
		var p: PackedStringArray = str(Game.cli.base_cam).split(",")
		cam.position = Vector2(float(p[0]), float(p[1]))
		cam.zoom = Vector2.ONE * float(p[2]) if p.size() > 2 else cam.zoom
	if sim.npcs.has(str(Game.cli.get("base_focus", ""))):
		cam.position = sim.npcs[Game.cli.base_focus].pos + Vector2(0, -60)
		cam.zoom = Vector2(0.9, 0.9)
	if Game.cli.has("base_skip"):
		sim.skip(int(Game.cli.base_skip))
	if Game.cli.has("base_ui"):
		call_deferred("_cli_ui", str(Game.cli.base_ui))
	Game.maybe_cli_capture(30)


func _add_npc_view(id: String) -> void:
	if npc_views.has(id) or not sim.npcs.has(id):
		return
	var v := NpcView.new()
	add_child(v)
	v.setup(sim, id)
	npc_views[id] = v


func _on_reloaded(_w: PackedStringArray) -> void:
	sim = Game.base
	for id in sim.data.npc_order:
		_add_npc_view(id)
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
			dir.y -= 1
		if Input.is_physical_key_pressed(KEY_S):
			dir.y += 1
	cam.position += dir * CAM_SPEED * delta / cam.zoom.x
	var br := sim.data.base_rect().grow(300)
	cam.position = cam.position.clamp(br.position, br.end)


# ================================================================ 마우스
func _world_mouse() -> Vector2:
	return get_global_mouse_position()


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
	for key in world.bubble_rects:
		if (world.bubble_rects[key] as Rect2).grow(6).has_point(p):
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
	world.hover_fid = "" if n != "" else sim.data.facility_at(p)
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
	var z := clampf(cam.zoom.x * k, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)


func _left_click(p: Vector2) -> void:
	if _pick_npc != "":
		var fid := sim.data.facility_at(p)
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
	var fid := sim.data.facility_at(p)
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
		hud.open_context(n, screen * get_viewport().get_screen_transform().get_scale())


func begin_clean_pick(npc_id: String) -> void:
	_pick_npc = npc_id
	world.pick_mode = true
	hud.set_banner("%s: 청소할 장소를 클릭하세요 (우클릭·Esc 취소)" % sim.data.npc_name(npc_id))


func _end_pick() -> void:
	_pick_npc = ""
	world.pick_mode = false
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
			hud.open_context(p[1], get_viewport().get_canvas_transform() * (v.position + Vector2(20, -40)))
		"clean":
			begin_clean_pick(p[1])
		"debug":
			hud.toggle_debug()
		"sortie":
			hud.open_sortie()
		"sortie_go":   # 기지 → 전투 배치 (편성) 바로
			sortie(Game.data.stage_order[0])
		"battle_go":   # 기지 → 전투 바로 (훈련 1단계 반영 확인용)
			sim.progression["a_dan"] = {"training": 2}
			Game.sortie(Game.data.stage_order[0])
			Game.start_battle.call_deferred()
