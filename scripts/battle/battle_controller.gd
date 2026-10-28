class_name BattleController
extends Node
## 전투 상태 머신 (GDD 4절). 표현(2D/3D/HUD)과 완전히 분리된 순수 규칙 계층.
## PREPARE → INITIATIVE → ROUND_START → ACTOR_START → (PLAYER_COMMAND|ENEMY_AI)
## → ACTION_RESOLVE → ACTOR_CONTINUE|ACTOR_END → NEXT_ACTOR → ROUND_END → ... → RESULT

enum State { IDLE, PREPARE, INITIATIVE, ROUND_START, ACTOR_START, PLAYER_COMMAND, ENEMY_AI, ACTION_RESOLVE, ACTOR_END, ROUND_END, RESULT }

signal state_changed(state: int)
signal battle_started()
signal initiative_decided(first_team: String, reason: String)
signal round_started(round_no: int, queue: Array)
signal actor_started(unit: UnitRuntime, recovered: int)
signal awaiting_command(unit: UnitRuntime)
signal actor_ended(unit: UnitRuntime, reason: String)
signal ap_changed(unit: UnitRuntime)
signal action_resolved(event: Dictionary)
signal unit_moved(unit: UnitRuntime, from_key: String, to_key: String)
signal units_swapped(a: UnitRuntime, b: UnitRuntime)
signal weapon_changed(unit: UnitRuntime)
signal unit_died(unit: UnitRuntime)
## 차례 시작 상태 이상 적용 (출혈·화상 피해, 재생 회복, 동상 폭발, 기절): {unit, results, text}
signal status_ticked(event: Dictionary)
signal battle_ended(winner: String)
signal log_message(text: String)
signal command_rejected(reason: String)

var slots := SlotManager.new()
var actions: Dictionary = {}            # id -> ActionData
var rng := RandomNumberGenerator.new()
var seed_value: int = 12345
var ambush_mode: String = "none"        # "none" | "ally" | "enemy"
var enemy_delay: float = 0.7            # 적 행동 간 연출 대기 (테스트에서는 0)
var state: int = State.IDLE
var round_no: int = 0
var queue: Array[UnitRuntime] = []
var queue_pos: int = 0
var current: UnitRuntime = null
var first_team: String = ""
var initiative_reason: String = ""
var winner: String = ""
var log_lines: PackedStringArray = []
var _next_instance_id: int = 1
var _roster: Array = []                 # [{data, row, index}]
var _enemy_turn_running := false
## true 면 선공 판정 뒤 첫 라운드를 바로 시작하지 않고 begin_rounds() 를 기다린다 (동전 연출용)
var wait_for_intro := false
var coin_face: String = ""              # 일반 전투 동전 결과: "front"(앞면=아군 선공) | "back" | ""(기습·매복)


func setup(p_actions: Dictionary, roster: Array, p_seed: int, p_ambush: String) -> void:
	actions = p_actions
	_roster = roster
	seed_value = p_seed
	ambush_mode = p_ambush


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)


func _log(text: String) -> void:
	log_lines.append(text)
	log_message.emit(text)


## 전투(재)시작: AP, HP, 슬롯, 큐 모두 초기화.
func start_battle() -> void:
	_set_state(State.PREPARE)
	rng.seed = seed_value
	slots.clear()
	log_lines.clear()
	queue.clear()
	queue_pos = 0
	current = null
	winner = ""
	round_no = 0
	_next_instance_id = 1
	for entry in _roster:
		var u := UnitRuntime.create(entry.data, _next_instance_id, entry.row, entry.index)
		_next_instance_id += 1
		# 기지(아웃게임)에서 들고 온 몸 상태: 남은 체력·상태 이상 (없으면 최대 체력, 상태 없음)
		if entry.has("hp"):
			u.hp = clampi(int(entry.hp), 1, u.data.max_hp)
		for sid in entry.get("statuses", []):
			u.add_status(str(sid))
		slots.add_unit(u)
	_log("전투 준비: 아군 %d / 적군 %d (seed %d)" % [slots.living_units("ally").size(), slots.living_units("enemy").size(), seed_value])
	battle_started.emit()
	_decide_initiative()
	if not wait_for_intro:
		_start_round()


## 선공 연출(동전)이 끝난 뒤 첫 라운드 시작
func begin_rounds() -> void:
	if state == State.INITIATIVE:
		_start_round()


func _decide_initiative() -> void:
	_set_state(State.INITIATIVE)
	coin_face = ""
	match ambush_mode:
		"ally":
			first_team = "ally"
			initiative_reason = "아군 기습 — 아군 선공"
		"enemy":
			first_team = "enemy"
			initiative_reason = "적 매복 — 적 선공"
		_:
			var coin := rng.randi() % 2
			first_team = "ally" if coin == 0 else "enemy"
			coin_face = "front" if coin == 0 else "back"
			initiative_reason = "동전 %s — %s 선공" % ["앞면" if coin == 0 else "뒷면", "아군" if first_team == "ally" else "적"]
	_log("선공 판정: " + initiative_reason)
	initiative_decided.emit(first_team, initiative_reason)


func _start_round() -> void:
	round_no += 1
	_set_state(State.ROUND_START)
	queue = TurnScheduler.build_round_queue(slots.all_units(), round_no, first_team)
	queue_pos = 0
	var names := PackedStringArray()
	for u in queue:
		names.append(u.display_name())
	_log("라운드 %d 시작: %s" % [round_no, " → ".join(names)])
	round_started.emit(round_no, queue)
	_next_actor()


func _check_end() -> bool:
	if slots.living_units("enemy").is_empty():
		winner = "ally"
	elif slots.living_units("ally").is_empty():
		winner = "enemy"
	else:
		return false
	_set_state(State.RESULT)
	_log("전투 종료: %s 승리" % ("아군" if winner == "ally" else "적"))
	battle_ended.emit(winner)
	return true


func _next_actor() -> void:
	if _check_end():
		return
	while queue_pos < queue.size() and not queue[queue_pos].alive:
		queue_pos += 1
	if queue_pos >= queue.size():
		_set_state(State.ROUND_END)
		_log("라운드 %d 종료" % round_no)
		_start_round()
		return
	current = queue[queue_pos]
	queue_pos += 1
	_actor_start()


func _actor_start() -> void:
	_set_state(State.ACTOR_START)
	current.actions_this_turn = 0
	# 상태 이상 먼저 (출혈·화상 피해 · 동상 · 기절) → 그다음 행동
	var st := StatusRules.turn_start(current)
	if not st.results.is_empty() or not st.texts.is_empty():
		for t in st.texts:
			_log(t)
		status_ticked.emit({"unit": current, "results": st.results, "text": "\n".join(st.texts)})
		for r in st.results:
			if r.killed:
				unit_died.emit(r.target)
	if not current.alive:
		_end_actor("상태 이상으로 전투 불능")
		return
	var recovered := APComponent.start_turn_recover(current)
	_log("%s 차례 (AP +%d → %d/%d)" % [current.display_name(), recovered, current.ap, current.data.max_ap])
	actor_started.emit(current, recovered)
	ap_changed.emit(current)
	if st.skip:
		_end_actor("기절 — 행동 불가")
		return
	if current.ap <= 0:
		_end_actor("AP 0 — 자동 종료")
		return
	if current.team == "ally":
		_set_state(State.PLAYER_COMMAND)
		awaiting_command.emit(current)
	else:
		_run_enemy_turn()


func _after_action() -> void:
	if _check_end():
		return
	if current.ap <= 0:
		_end_actor("AP 소진 — 자동 종료")
		return
	if current.team == "ally":
		_set_state(State.PLAYER_COMMAND)
		awaiting_command.emit(current)


func _end_actor(reason: String) -> void:
	_set_state(State.ACTOR_END)
	var u := current
	_log("%s 턴 종료 (%s, 이월 AP %d)" % [u.display_name(), reason, u.ap])
	for sid in u.statuses.duplicate():
		if StatusCatalog.get_def(sid).get("expires", "") == "own_turn_end":
			u.remove_status(sid)
	if u.alive:
		var gone := StatusRules.turn_end(u)
		if not gone.is_empty():
			_log("%s: %s 풀림" % [u.display_name(), ", ".join(gone.map(func(x): return StatusCatalog.get_def(x).name))])
	actor_ended.emit(u, reason)
	_next_actor()


func _run_enemy_turn() -> void:
	_set_state(State.ENEMY_AI)
	_enemy_turn_running = true
	while true:
		if enemy_delay > 0.0 and is_inside_tree():
			await get_tree().create_timer(enemy_delay).timeout
		if state == State.RESULT:
			_enemy_turn_running = false
			return
		var decision := EnemyAI.decide(current, actions, slots, rng)
		if decision.is_empty():
			break
		var ok := _execute(current, decision.action, decision.target)
		if not ok:
			break
		if _check_end():
			_enemy_turn_running = false
			return
		if current.ap <= 0:
			_enemy_turn_running = false
			_end_actor("AP 소진 — 자동 종료")
			return
	_enemy_turn_running = false
	if enemy_delay > 0.0 and is_inside_tree():
		await get_tree().create_timer(enemy_delay * 0.5).timeout
	_end_actor("AI 행동 종료")


# ---------------------------------------------------------------- 공통 실행 경로
## can_execute → pay_ap → resolve → emit_event
func _execute(actor: UnitRuntime, action: ActionData, target: UnitRuntime) -> bool:
	var reason := TargetValidator.block_reason(action, actor, target, slots)
	if reason != "":
		command_rejected.emit(reason)
		return false
	if not APComponent.can_pay(actor, action.ap_cost):
		command_rejected.emit("AP가 부족합니다. (필요 %d)" % action.ap_cost)
		return false
	# 실명: 고른 대상 대신 유효 대상 중 무작위
	var aim := StatusRules.blind_target(action, actor, target, slots, rng)
	if aim != target:
		_log("%s: 실명 — 대상이 무작위로 바뀜 (%s → %s)" % [actor.display_name(), target.display_name(), aim.display_name()])
		target = aim
	_set_state(State.ACTION_RESOLVE)
	APComponent.pay(actor, action.ap_cost)
	actor.actions_this_turn += 1
	var event := ActionResolver.resolve(action, actor, target, rng)
	_log(event.text)
	ap_changed.emit(actor)
	if (event.applied as Array).any(func(x): return StatusCatalog.effect_of(x.status) in ["slow", "haste"]):
		_resort_rest()
	action_resolved.emit(event)
	for r in event.results:
		if r.kind == "ap":
			ap_changed.emit(r.target)
		if r.get("killed", false):
			unit_died.emit(r.target)
	# 넉백·끌어당김: 맞은 뒤 자리 옮김 (같은 편과 자리 바꿈 포함)
	for a in event.applied:
		if StatusCatalog.is_instant(a.status):
			_displace(a.target, a.status, int(a.get("value", 1)))
	return true


func _displace(u: UnitRuntime, sid: String, value: int) -> void:
	var res := StatusRules.displace(u, sid, value, slots)
	var nm: String = StatusCatalog.get_def(sid).name
	if not res.ok:
		if str(res.get("reason", "")) != "":
			_log(res.reason)
		return
	if res.kind == "move":
		_log("%s: %s — %s → %s" % [u.display_name(), nm, res.from, res.to])
		unit_moved.emit(u, res.from, res.to)
	else:
		_log("%s: %s — %s 와 자리 바뀜" % [u.display_name(), nm, res.other.display_name()])
		units_swapped.emit(u, res.other)


## 감속·가속이 걸리면 이번 라운드에 아직 차례가 안 온 유닛들 순서를 지금 속도로 다시 정렬
func _resort_rest() -> void:
	if queue_pos >= queue.size():
		return
	var rest: Array[UnitRuntime] = []
	rest.assign(queue.slice(queue_pos))
	rest = TurnScheduler.sort_by_speed(rest)
	for i in rest.size():
		queue[queue_pos + i] = rest[i]
	round_started.emit(round_no, queue)   # HUD 행동 순서 갱신


# ---------------------------------------------------------------- 플레이어 명령 API
func is_player_turn() -> bool:
	return state == State.PLAYER_COMMAND and current != null and current.team == "ally"


func get_action(action_id: String) -> ActionData:
	return actions.get(action_id, null)


## HUD 버튼 구성용. [{id, name, cost, enabled, reason, kind}]
func get_command_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current == null:
		return out
	for sid in current.data.skill_ids:
		var a: ActionData = actions.get(sid, null)
		if a == null:
			continue
		var enabled := true
		var reason := ""
		if not APComponent.can_pay(current, a.ap_cost):
			enabled = false
			reason = "AP 부족 (필요 %d, 보유 %d)" % [a.ap_cost, current.ap]
		elif TargetValidator.valid_targets(a, current, slots).is_empty():
			enabled = false
			reason = "유효한 대상이 없습니다."
		var desc := a.description
		for st in a.statuses:
			desc += "\n상태 이상: " + SkillStatusData.summary(st)
		out.append({"id": a.id, "name": a.display_name, "cost": a.ap_cost, "enabled": enabled, "reason": reason, "kind": a.kind, "desc": desc})
	var mv: ActionData = actions.get("move", null)
	if mv != null:
		var can := APComponent.can_pay(current, mv.ap_cost) and current.can_be_moved()
		var why := "" if can else ("AP 부족" if current.can_be_moved() else ("구속 — 자리 이동 불가" if current.has_effect("root") else "자리 이동 불가 (부상·큰 몸집)"))
		out.append({"id": "move", "name": mv.display_name, "cost": mv.ap_cost, "enabled": can, "reason": why, "kind": "move", "desc": mv.description})
	var wp: ActionData = actions.get("weapon", null)
	if wp != null:
		var can := APComponent.can_pay(current, wp.ap_cost) and current.data.weapons.size() > 1
		var reason := ""
		if current.data.weapons.size() <= 1:
			reason = "교체할 무기가 없습니다."
		elif not APComponent.can_pay(current, wp.ap_cost):
			reason = "AP 부족"
		out.append({"id": "weapon", "name": wp.display_name, "cost": wp.ap_cost, "enabled": can, "reason": reason, "kind": "weapon", "desc": wp.description})
	return out


func get_valid_targets(action_id: String) -> Array[UnitRuntime]:
	var a: ActionData = actions.get(action_id, null)
	if a == null or current == null:
		return []
	return TargetValidator.valid_targets(a, current, slots)


func get_target_block_reason(action_id: String, target: UnitRuntime) -> String:
	var a: ActionData = actions.get(action_id, null)
	if a == null or current == null:
		return "행동이 없습니다."
	return TargetValidator.block_reason(a, current, target, slots)


## 이동 가능한 슬롯 목록 [{key, kind: "move"|"swap", other}]
func get_move_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if current == null or not current.can_be_moved():
		return out
	for key in slots.team_slot_keys(current.team):
		if key == current.slot_key():
			continue
		var other := slots.unit_at(key)
		if other != null and not other.can_be_moved():
			continue   # 부상·상태이상·큰 몸집: 표시하지 않음
		out.append({"key": key, "kind": "move" if other == null else "swap", "other": other})
	return out


func player_execute(action_id: String, target: UnitRuntime) -> bool:
	if not is_player_turn():
		command_rejected.emit("지금은 명령할 수 없습니다.")
		return false
	var a: ActionData = actions.get(action_id, null)
	if a == null:
		command_rejected.emit("알 수 없는 행동입니다.")
		return false
	var ok := _execute(current, a, target)
	if ok:
		_after_action()
	return ok


func player_move(slot_key: String) -> bool:
	if not is_player_turn():
		command_rejected.emit("지금은 명령할 수 없습니다.")
		return false
	var mv: ActionData = actions.get("move", null)
	if mv == null:
		return false
	if not APComponent.can_pay(current, mv.ap_cost):
		command_rejected.emit("AP가 부족합니다. (필요 %d)" % mv.ap_cost)
		return false
	var info := SlotManager.parse_key(slot_key)
	if info.team != current.team:
		command_rejected.emit("아군 슬롯만 선택할 수 있습니다.")
		return false
	if slot_key == current.slot_key():
		command_rejected.emit("현재 위치입니다.")
		return false
	_set_state(State.ACTION_RESOLVE)
	var from_key := current.slot_key()
	var res := slots.move_or_swap(current, slot_key)
	if not res.ok:
		command_rejected.emit(res.reason)
		_set_state(State.PLAYER_COMMAND)
		return false
	APComponent.pay(current, mv.ap_cost)  # 명령자 AP만 소모
	current.actions_this_turn += 1
	ap_changed.emit(current)
	if res.kind == "move":
		_log("%s 이동: %s → %s" % [current.display_name(), from_key, slot_key])
		unit_moved.emit(current, from_key, slot_key)
	else:
		_log("%s ↔ %s 자리 교환" % [current.display_name(), res.other.display_name()])
		units_swapped.emit(current, res.other)
	_after_action()
	return true


func player_change_weapon() -> bool:
	if not is_player_turn():
		command_rejected.emit("지금은 명령할 수 없습니다.")
		return false
	var wp: ActionData = actions.get("weapon", null)
	if wp == null:
		return false
	if current.data.weapons.size() <= 1:
		command_rejected.emit("교체할 무기가 없습니다.")
		return false
	if not APComponent.can_pay(current, wp.ap_cost):
		command_rejected.emit("AP가 부족합니다. (필요 %d)" % wp.ap_cost)
		return false
	_set_state(State.ACTION_RESOLVE)
	APComponent.pay(current, wp.ap_cost)
	current.actions_this_turn += 1
	current.weapon_index = (current.weapon_index + 1) % current.data.weapons.size()
	_log("%s 무기 변경 → %s" % [current.display_name(), current.current_weapon().name])
	ap_changed.emit(current)
	weapon_changed.emit(current)
	_after_action()
	return true


## 무기 슬롯 index(0 주무기, 1·2 보조무기)를 장착. AP 는 무기 변경 비용(1).
func player_equip_weapon(index: int) -> bool:
	if not is_player_turn():
		command_rejected.emit("지금은 명령할 수 없습니다.")
		return false
	var wp: ActionData = actions.get("weapon", null)
	if wp == null:
		return false
	if index < 0 or index >= current.data.weapons.size():
		command_rejected.emit("빈 무기 칸입니다.")
		return false
	if index == current.weapon_index:
		command_rejected.emit("이미 장착 중입니다.")
		return false
	if not APComponent.can_pay(current, wp.ap_cost):
		command_rejected.emit("AP가 부족합니다. (필요 %d)" % wp.ap_cost)
		return false
	_set_state(State.ACTION_RESOLVE)
	APComponent.pay(current, wp.ap_cost)
	current.actions_this_turn += 1
	current.weapon_index = index
	_log("%s 무기 장착 → %s" % [current.display_name(), current.current_weapon().name])
	ap_changed.emit(current)
	weapon_changed.emit(current)
	_after_action()
	return true


func player_end_turn() -> bool:
	if not is_player_turn():
		command_rejected.emit("지금은 턴을 종료할 수 없습니다.")
		return false
	_end_actor("플레이어 종료")
	return true


## 디버그 패널용 요약
func debug_snapshot() -> Dictionary:
	var q := PackedStringArray()
	for i in queue.size():
		var u := queue[i]
		var mark := ">" if (i == queue_pos - 1 and u == current) else (" " if u.alive else "x")
		q.append("%s%s(%d)" % [mark, u.display_name(), u.data.speed])
	return {
		"round": round_no, "state": State.keys()[state], "seed": seed_value, "ambush": ambush_mode,
		"first_team": first_team, "queue": q, "current": current.debug_string() if current else "-",
	}
