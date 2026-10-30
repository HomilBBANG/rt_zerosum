class_name BaseSim
extends RefCounted
## 아웃게임 기지 시뮬레이션 (화면과 분리 — 헤드리스 테스트 가능).
## 시계 · 시설 해금 · 대원 주간 일정 이동 · 대화/엿듣기/요청 · 업무/외부 의뢰 ·
## 주간 결산(주급 = 기본 주급 × 납품 비율) · 전리품 창고 · 납품 · 월 1회 장군 점검(아이템 요구 · 충성심) · 훈련/제작/강화 · 저장/불러오기 ·
## 대원 몸 상태(체력·상태 이상·피로·친밀도) · 오브젝트(침대·소파·의자·의무침대) · 식재료 · PX 선물 · 의무실 · 전투 발생 규칙.
## 처리 순서 (매 게임 분): 날짜 전환(결산 → 월 전환) → 정각 → 점검 → 작업실 → 대원 → 대화.
## 날짜가 바뀌는 판단은 시계만 하고, UI 는 이 클래스의 함수만 호출한다 (03_IMPLEMENTATION_HANDOFF 4절).

signal hour_changed(minute: int)
signal day_changed(day: int)
signal month_changed(key: String)
signal room_unlocked(fid: String)
signal npc_state_changed(npc_id: String)
signal loot_changed()
signal job_completed(job: Dictionary)
signal inspection_completed(record: Dictionary)
signal statement_ready(statement: Dictionary)
signal notice(text: String)
## 신 해금 캐릭터의 정체가 드러남 (신앙 탭 → 기적)
signal divine_revealed(character_id: String)
signal quest_started(quest_id: String)
signal quest_step(quest_id: String, step: int)
signal quest_completed(quest_id: String)
signal cutscene_queued(cutscene_id: String)
signal battle_triggered(pending: Dictionary)
signal research_completed(research_id: String)
signal leveled_up(character_id: String, level: int)

const SAVE_VERSION := 1

var data: OutgameData
var battle: GameData                 # 전투 캐릭터·아이템 (초기 장비·무기 이름). 없으면 무기고 비어 있음
var clock := WorldClock.new()
var rng := RandomNumberGenerator.new()
var ledger := EconomyLedger.new()
var unlocked: Dictionary = {}        # fid → true
var loot: Dictionary = {}            # 전리품 창고: 아이템 id(data/supply.xlsx 아이템) → 개수 — 전투 승리 · 대원 선물로 얻고 납품 · 장군 요구에 씀
var deliveries: Dictionary = {}      # 주 번호(문자열) → {req: {아이템: 개수}, done: {아이템: 개수}} 그 주 납품 목록 (처음 볼 때 진행률로 정함)
var loyalty: int = 50                # 장군 충성심 0~100
var last_loot: Array = []            # 마지막 전투 승리 전리품 [{item, name, count}] (결과 화면 표시용, 저장 안 함)
var npcs: Dictionary = {}            # npc id → NpcAgent
var chats: Array = []                # [{key, conv, a, b, facility, end, story}]
var jobs: Array = []                 # [{uid, contract, npc, state, minute}]
var claimed_contracts: Dictionary = {}
var opened_contracts: Dictionary = {}
var request_state: Dictionary = {}   # 요청 id → "accepted"
var conv_counts: Dictionary = {}     # 대화이벤트 id → 발생 횟수
var heard: Dictionary = {}           # 대화이벤트 id → 엿들은 횟수
var story_seen: Dictionary = {}      # 스토리 이벤트 id → 처음 엿들은 시각 라벨
var inspections: Dictionary = {}     # "YYYY-MM" → {month, minute, done, item, count, line, answer("" 대답 전 · give · refuse), week, date}
var progression: Dictionary = {}     # 전투 캐릭터 id → {training, level, xp, skills: [배운 스킬 트리 노드 id], faith, faith_skills: [배운 신앙 스킬 id], miracles: [배운 기적 id]}
var divine_unlocked: Dictionary = {}  # 정체(신)가 드러난 캐릭터 id → true (처음부터 해금인 캐릭터는 넣지 않아도 신)
var quests: Dictionary = {}          # 퀘스트 id → {state: active|done, step(지금 단계 번호), base(그 단계 시작 때 횟수), started, finished(일차)}
var talk_counts: Dictionary = {}     # 대원 id → 지휘관과 대화한 횟수 (퀘스트 '대원과 대화' 단계)
var _questing := false
var cutscene_queue: Array = []       # 재생 기다리는 컷씬 id (기지 화면이 창 없을 때 차례로 재생)
var cutscenes_seen: Dictionary = {}  # 본 컷씬 id → 처음 본 일차 (이어진 컷씬 포함)
var inventory: Array = []            # [{uid, item, plus, owner(캐릭터 id 또는 ""), slot}]
var workshop: Dictionary = {}        # {kind: craft|enhance, recipe?, uid?, remaining, total}
var researched: Dictionary = {}      # 연구 id → true (완료)
var research: Dictionary = {}        # 진행 중 연구 {id, remaining, total} (한 번에 하나)
var counters: Dictionary = {"job": 0, "inv": 0, "chat": 0}
var log_lines: Array = []
var chars: Dictionary = {}           # 전투 캐릭터 id → {hp, statuses, fatigue, affinity, talk_day} (기지·전투 공통 몸 상태)
var seat_owner: Dictionary = {}      # 오브젝트 id → 대원 id
var food: int = 0                    # 식재료 (1 = 한 끼)
var water: int = 0                   # 물 (병) — 인벤토리에 보임. 아직 쓰는 곳 없음 (supply.xlsx 설정 water_start)
var gifts: Dictionary = {}           # PX 선물 id → 개수
var growth: Array = []               # 마지막 전투 결과의 성장 [{id, name, xp, level, ups}] (결과 화면 표시용, 저장 안 함)
var pending_battle: Dictionary = {}  # 발생했지만 아직 끝나지 않은 전투 {rule, name, stage, minute, label, allow_skip}
var battle_history: Array = []       # [{minute, label, stage, rule, winner}]
var _minute: int = 0                 # 마지막으로 처리한 게임 분
var _day: int = 0
var _month: String = ""
var _changes: Dictionary = {}        # npc id → {weekday: {minute: true}} 일정이 바뀌는 시각


static func create(p_data: OutgameData, p_battle: GameData = null) -> BaseSim:
	var s := BaseSim.new()
	s.data = p_data
	s.battle = p_battle
	s._new_game()
	return s


func _new_game() -> void:
	clock.setup(data.text("start_date", "2048-04-07"), OutgameData.parse_hm(data.text("start_time", "08:00"), 480))
	rng.seed = data.inum("seed", 2048)
	ledger.cash = data.inum("start_cash", 150)
	for fid in data.facility_order:
		if data.facilities[fid].initial_open:
			unlocked[fid] = true
	loyalty = supply().inum("loyalty_start", 50)
	_add_missing_npcs()
	_init_inventory()
	food = data.inum("food_start", 10)
	water = supply().inum("water_start", 12)
	_minute = clock.minute_int()
	_day = clock.day_index(_minute)
	_month = clock.month_key(_minute)
	_schedule_inspection(_minute)
	_rebuild_changes()
	_log("기지 운영 시작")
	for id in data.npc_order:
		_npc_minute(npcs[id], _minute)
	trigger_cutscenes("new_game")
	trigger_cutscenes("day", "", _day + 1)
	check_divine()   # 처음부터 시작하는 퀘스트 · 이미 조건을 채운 신


func _add_missing_npcs() -> void:
	for id in data.npc_order:
		if npcs.has(id):
			continue
		var d: Dictionary = data.npcs[id]
		var n := NpcAgent.new()
		n.id = id
		n.name = d.name
		n.character_id = d.character_id
		n.sprite = d.sprite
		n.height_cm = d.height_cm
		n.facility = d.start if data.facilities.has(d.start) else data.facility_order[0]
		n.dest = n.facility
		n.dest_x = _slot_x(n, n.facility)
		n.pos = Vector2(n.dest_x, data.floor_line(n.facility))
		n.state = NpcAgent.STAYING
		npcs[id] = n


func _init_inventory() -> void:
	if battle == null:
		return
	for id in data.npc_order:
		var cid: String = data.npcs[id].character_id
		var u: UnitData = GameData._find(battle.allies, cid)
		if u == null:
			continue
		for i in u.weapons.size():
			counters.inv += 1
			inventory.append({"uid": "w%d" % counters.inv, "item": str(u.weapons[i].id), "plus": 0, "owner": cid, "slot": i})


## 실행 중 엑셀·일정 파일이 바뀌면 새 데이터로 교체 (상태는 유지)
func set_data(newer: OutgameData) -> void:
	data = newer
	for fid in data.facility_order:
		if data.facilities[fid].initial_open:
			unlocked[fid] = true
	_add_missing_npcs()
	for n in npcs.values():
		var d: Dictionary = data.npcs.get(n.id, {})
		if not d.is_empty():
			n.name = d.name
			n.character_id = d.character_id
			n.sprite = d.sprite
			n.height_cm = d.height_cm
		n.need_think = true
	_rebuild_changes()


# ================================================================ 시간
func minute() -> int:
	return _minute


func week_days() -> int:
	return maxi(1, data.inum("week_days", 7))


func week_now() -> int:
	return clock.week_index(week_days(), _minute)


func minutes_to_settlement() -> int:
	return (week_now() + 1) * week_days() * 1440 - _minute


## 실시간 진행 (게임 분, 소수 허용). 분 경계마다 이벤트를 순서대로 처리
func advance(dm: float) -> void:
	var target := clock.total_minutes + dm
	while clock.total_minutes < target - 0.000001:
		var next_int := float(floori(clock.total_minutes) + 1)
		var step := minf(target, next_int) - clock.total_minutes
		_move(step)
		clock.total_minutes += step
		var m := clock.minute_int()
		while _minute < m:
			_minute += 1
			_on_minute(_minute)


## 디버그 시간 건너뛰기: 1분씩 실제로 진행 (이동·작업·이벤트가 빠짐없이 같은 순서로 처리됨)
func skip(minutes: int) -> void:
	advance(float(minutes))


func skip_to_next_day() -> void:
	skip((_day + 1) * 1440 - _minute)


func skip_to_next_week() -> void:
	skip(minutes_to_settlement())


func skip_to_next_month() -> void:
	skip(clock.month_bounds(_minute).y - _minute)


func _on_minute(m: int) -> void:
	var day := clock.day_index(m)
	while _day < day:
		_day += 1
		_new_day(_day)
	if clock.minute_of_day(m) % 60 == 0:
		hour_changed.emit(m)
	_check_inspection(m)
	_check_battle_rules(m)
	_tick_workshop()
	_tick_research()
	for id in data.npc_order:
		if npcs.has(id):
			_tick_body(npcs[id])
			_npc_minute(npcs[id], m)
	_tick_chats(m)
	_try_conversations(m)


func _new_day(d: int) -> void:
	trigger_cutscenes("day", "", d + 1)
	check_divine()
	day_changed.emit(d)
	if d % week_days() == 0:
		_settle(floori(d / float(week_days())) - 1)
	var key := clock.month_key(d * 1440)
	if key != _month:
		_month = key
		month_changed.emit(key)
		_schedule_inspection(d * 1440)
	for n in npcs.values():
		n.need_think = true


# ================================================================ 해금
func is_unlocked(fid: String) -> bool:
	return unlocked.has(fid)


func _is_open(fid: String) -> bool:
	return unlocked.has(fid)


## {ok, msg}. 달러 부족 / 이미 해금 / 정상 결제
func try_unlock(fid: String) -> Dictionary:
	var f: Dictionary = data.facilities.get(fid, {})
	if f.is_empty():
		return {"ok": false, "msg": "없는 시설입니다"}
	if unlocked.has(fid):
		return {"ok": false, "msg": "이미 해금된 시설입니다"}
	var cost: int = f.cost
	if ledger.cash < cost:
		return {"ok": false, "msg": "달러가 부족합니다 ($%d 더 필요)" % (cost - ledger.cash)}
	if not ledger.post("unlock:" + fid, _minute, clock.label(_minute), "unlock", -cost, fid, "%s 해금" % data.facility_name(fid), week_now()):
		return {"ok": false, "msg": "이미 처리된 해금입니다"}
	unlocked[fid] = true
	for n in npcs.values():
		n.need_think = true   # 해금 → 일정 분기 재평가 (생활 변화)
	_log("%s 해금 (-$%d)" % [data.facility_name(fid), cost])
	room_unlocked.emit(fid)
	return {"ok": true, "msg": "%s 해금 완료" % data.facility_name(fid)}


# ================================================================ 대원 이동·일정
func _rebuild_changes() -> void:
	_changes.clear()
	for id in data.npc_order:
		var per := {}
		for wd in 7:
			per[wd] = {0: true}
		for b in data.schedules.get(id, {}).get("weekly_schedule", []):
			var wd := int(b.get("weekday", 0))
			if per.has(wd):
				per[wd][int(b.get("start_minute", 0))] = true
				per[wd][int(b.get("end_minute", 0))] = true
		_changes[id] = per


func reachable(from: String, to: String) -> bool:
	return RoomRouteService.reachable(data, from, to, _is_open)


## 지금 일정상 가야 할 곳 {facility, activity, reason, block}
func desired(n: NpcAgent, m: int = -1) -> Dictionary:
	var mm := _minute if m < 0 else m
	var sched: Dictionary = data.schedules.get(n.id, {})
	var from := n.facility
	return NpcScheduleResolver.destination(sched, clock.weekday(mm), clock.minute_of_day(mm), _is_open,
		func(f: String) -> bool: return unlocked.has(f) and reachable(from, f))


func _npc_minute(n: NpcAgent, m: int) -> void:
	match n.state:
		NpcAgent.PLAYER_DIALOGUE:
			return
		NpcAgent.UNAVAILABLE, NpcAgent.CLEANING, NpcAgent.ASSIGNED_WORK, NpcAgent.TRAINING:
			n.busy -= 1.0
			if n.busy <= 0.0:
				_finish_command(n)
			return
		NpcAgent.TREATMENT:
			n.busy -= 1.0
			if n.busy <= 0.0:
				var cs := cstate(n)
				cs.statuses = []
				_log("%s 치료 완료 — 상태 이상 없음, 이제 의무실 침대에서 휴식" % n.name)
				n.state = NpcAgent.RECOVERING
				npc_state_changed.emit(n.id)
			return
		NpcAgent.RECOVERING:
			if n.seat == "":
				_claim_seat_here(n, "medical")
			if float(cstate(n).hp) >= char_max_hp(ckey(n)):
				_log("%s 체력 회복 완료 (%d)" % [n.name, char_max_hp(ckey(n))])
				_finish_command(n)
			return
	var mod := clock.minute_of_day(m)
	var changes: Dictionary = _changes.get(n.id, {}).get(clock.weekday(m), {})
	if n.is_holding():
		# 플레이어가 보낸 이동·행동: 도착해서 그 행동을 하다가, 다음 일정 블록이 시작되면(또는 다 자면) 일정으로 복귀
		if n.state == NpcAgent.MOVING:
			return
		_try_meal(n, m)
		var slept := n.activity == "sleep" and float(cstate(n).fatigue) <= 0.0
		if not (changes.has(mod) or slept):
			return
		if slept:
			_log("%s 이(가) 푹 자고 일어났습니다" % n.name)
		n.command = {}
		_release_seat(n)
		n.need_think = true
	if not n.command.is_empty():
		return   # 지시 장소로 이동 중
	_try_meal(n, m)
	if not (n.need_think or changes.has(mod)):
		return
	n.need_think = false
	var want := desired(n, m)
	n.dest_reason = want.reason
	if n.state == NpcAgent.CHATTING:
		if want.facility == n.facility:
			return
		_end_chat_of(n, m)   # 일정 이동 때 대원끼리 대화는 끊길 수 있음 (10절 3)
	if want.facility == "":
		return
	n.activity = want.activity
	var seat := _pick_seat(n, want.facility, want.activity)
	if want.facility != n.dest or seat != n.seat:
		_go(n, want.facility, seat)
	elif n.state != NpcAgent.MOVING:
		n.state = NpcAgent.STAYING
	npc_state_changed.emit(n.id)


func _slot_x(n: NpcAgent, fid: String) -> float:
	var r := data.facility_rect(fid)
	if data.facilities[fid].tag == "출입":
		return r.position.x + 30.0
	var idx := maxi(0, data.npc_order.find(n.id))
	var cnt := maxi(1, data.npc_order.size())
	var frac := (float(idx) + 0.5) / float(cnt)
	return r.position.x + 44.0 + frac * (r.size.x - 88.0)


func _go(n: NpcAgent, fid: String, seat: String = "", at_x: float = NAN) -> bool:
	var route := RoomRouteService.find_path(data, n.facility, fid, _is_open)
	if route.is_empty():
		n.dest_reason = "%s 로 가는 길 없음" % data.facility_name(fid)
		return false
	_release_seat(n)
	if seat != "" and not seat_owner.has(seat):
		seat_owner[seat] = n.id
		n.seat = seat
	n.dest = fid
	n.dest_x = data.object_x(n.seat) if n.seat != "" else (at_x if not is_nan(at_x) else _slot_x(n, fid))
	n.path = RoomRouteService.waypoints(data, route, n.dest_x)
	n.state = NpcAgent.MOVING
	npc_state_changed.emit(n.id)
	return true


func _move(step: float) -> void:
	var speed := data.num("walk_speed", 90.0)
	for n in npcs.values():
		if n.state != NpcAgent.MOVING:
			continue
		var dist := speed * step * (data.num("run_speed_mult", 2.2) if n.running else 1.0)
		while dist > 0.0 and n.path.size() > 0:
			var tgt: Vector2 = n.path[0]
			var d: float = n.pos.distance_to(tgt)
			if absf(tgt.x - n.pos.x) > 0.5:
				n.facing = 1 if tgt.x > n.pos.x else -1
			if d <= dist:
				n.pos = tgt
				dist -= d
				n.path.remove_at(0)
			else:
				n.pos += (tgt - n.pos) / d * dist
				dist = 0.0
		var here := data.facility_at(n.pos + Vector2(0, -4))
		if here != "":
			n.facility = here
		if n.path.is_empty():
			_arrive(n)


func _arrive(n: NpcAgent) -> void:
	n.facility = n.dest
	n.running = false
	var c := n.command
	if c.is_empty():
		n.state = NpcAgent.STAYING
	else:
		match str(c.type):
			"move":
				n.state = NpcAgent.STAYING
				n.activity = str(c.get("activity", "idle"))
			"train":
				n.state = NpcAgent.TRAINING
				n.busy = data.num("train_minutes", 120.0)
			"medical":
				if not (cstate(n).statuses as Array).is_empty():
					n.state = NpcAgent.TREATMENT
					n.busy = data.num("treat_minutes", 60.0)
				else:
					n.state = NpcAgent.RECOVERING
			"job":
				var j: Dictionary = data.jobs.get(str(c.contract), {})
				n.busy = float(j.get("minutes", 60))
				n.state = NpcAgent.UNAVAILABLE if j.get("kind", "task") == "external" else NpcAgent.ASSIGNED_WORK
				var job := _job(str(c.uid))
				if not job.is_empty():
					job.state = "working"
				if n.state == NpcAgent.UNAVAILABLE:
					_log("%s 이(가) 정문을 나섰습니다 (%s)" % [n.name, j.get("name", "")])
	npc_state_changed.emit(n.id)


# ================================================================ 지휘관 대화 · 요청
## 캐릭터 클릭 → 대화. {lines, request(요청 dict 또는 {})}
func begin_dialogue(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null or n.state == NpcAgent.UNAVAILABLE:
		return {}
	if n.state == NpcAgent.CHATTING:
		_end_chat_of(n, _minute)
	if n.state != NpcAgent.PLAYER_DIALOGUE:
		n.resume_state = n.state
		n.state = NpcAgent.PLAYER_DIALOGUE
	npc_state_changed.emit(n.id)
	talk_counts[npc_id] = int(talk_counts.get(npc_id, 0)) + 1
	check_divine()   # 퀘스트 '대원과 대화' 단계
	var cs := cstate(n)
	var gift := {}
	if int(cs.get("talk_day", -1)) != _day:   # 하루 첫 대화 → 친밀도 조금 + 확률로 선물(전리품, supply.xlsx 대원 선물)
		cs.talk_day = _day
		_add_affinity(n, data.num("affinity_talk", 1.0))
		gift = _crew_gift(n)
	var req := active_request(npc_id)
	if not req.is_empty():
		return {"lines": data.dialogues.get(req.dialogue, []), "request": req, "affinity_need": -1, "new_talk": false, "gift": gift}
	# 친밀도 대화: 해금됐지만 안 본 대화부터, 다 봤으면 해금된 가장 높은 단계, 없으면 기본 대사
	var dlg := str(data.npcs.get(npc_id, {}).get("talk", ""))
	var need := -1
	var fresh := false
	var t := pending_affinity_talk(npc_id)
	if not t.is_empty():
		fresh = true
		var seen: Array = cs.get("seen_talks", [])
		seen.append(t.id)
		cs.seen_talks = seen
	else:
		var un := unlocked_affinity_talks(npc_id)
		t = un.back() if not un.is_empty() else {}
	if not t.is_empty():
		dlg = t.dialogue
		need = int(t.need)
		if fresh:
			_log("%s 친밀도 %d 대화를 봤습니다" % [n.name, need])
			npc_state_changed.emit(n.id)
	var cut := _take_cutscene("talk", npc_id)   # 그 대원에게 말 걸기 컷씬이 있으면 평소 대사 대신
	return {"lines": data.dialogues.get(dlg, []), "request": {}, "affinity_need": need, "new_talk": fresh, "cutscene": cut, "gift": gift}


## 친밀도로 해금된 대화 (낮은 단계부터)
func unlocked_affinity_talks(npc_id: String) -> Array:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return []
	var a := float(cstate(n).affinity)
	return (data.affinity_talks.get(npc_id, []) as Array).filter(func(t): return a >= float(t.need))


## 해금됐지만 아직 안 본 가장 낮은 단계의 친밀도 대화 (머리 위 ♥), 없으면 {}
func pending_affinity_talk(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return {}
	var seen: Array = cstate(n).get("seen_talks", [])
	for t in unlocked_affinity_talks(npc_id):
		if not seen.has(t.id):
			return t
	return {}


## 다음 친밀도 대화 기준 (없으면 -1)
func next_affinity_need(npc_id: String) -> int:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return -1
	for t in data.affinity_talks.get(npc_id, []):
		if float(cstate(n).affinity) < float(t.need):
			return int(t.need)
	return -1


func end_dialogue(npc_id: String) -> void:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null or n.state != NpcAgent.PLAYER_DIALOGUE:
		return
	n.state = n.resume_state if n.resume_state != "" and n.resume_state != NpcAgent.CHATTING else NpcAgent.STAYING
	if n.state == NpcAgent.MOVING and n.path.is_empty():
		n.state = NpcAgent.STAYING
	n.need_think = true
	npc_state_changed.emit(n.id)


## 머리 위 '!' 요청 (없으면 {})
func active_request(npc_id: String) -> Dictionary:
	for rid in data.request_order:
		var q: Dictionary = data.requests[rid]
		if q.npc != npc_id or request_state.has(rid):
			continue
		if q.start_day != "" and _day < clock.day_of(q.start_day):
			continue
		return q
	return {}


func accept_request(rid: String) -> Dictionary:
	var q: Dictionary = data.requests.get(rid, {})
	if q.is_empty():
		return {"ok": false, "msg": "없는 요청"}
	if request_state.has(rid):
		return {"ok": false, "msg": "이미 수락한 요청입니다"}
	request_state[rid] = "accepted"
	if npcs.has(q.npc):
		_add_affinity(npcs[q.npc], data.num("affinity_request", 5.0))
	var eff: String = q.effect
	var msg := "요청 수락"
	# 수락효과: "의뢰:의뢰 id" · "신앙:5"(그 대원 신앙도 +5) — 여러 개는 , 로
	for part in eff.split(",", false):
		part = part.strip_edges()
		if part.begins_with("의뢰:"):
			var cid := part.substr(3).strip_edges()
			opened_contracts[cid] = true
			msg = "요청 수락 — 의뢰 '%s' 이(가) 열렸습니다" % data.jobs.get(cid, {}).get("name", cid)
		elif part.begins_with("신앙:"):
			var ch := str(data.npcs.get(q.npc, {}).get("character_id", ""))
			if ch != "":
				var want := int(part.substr(3).strip_edges())
				msg += " · " + _faith_text(ch, add_faith(ch, want, "요청 수락"), want)
	_log("%s 의 요청 수락 (%s)" % [data.npc_name(q.npc), rid])
	return {"ok": true, "msg": msg, "lines": data.dialogues.get(q.accept_dialogue, [])}


# ================================================================ 대원끼리 대화 · 엿듣기
func _can_chat(n: NpcAgent, m: int) -> bool:
	return n.state == NpcAgent.STAYING and n.command.is_empty() and n.activity in OutgameData.CHAT_ACTIVITIES \
		and m - n.last_chat >= data.inum("chat_cooldown", 180)


func _try_conversations(m: int) -> void:
	for c in data.conversations:
		if int(conv_counts.get(c.id, 0)) >= int(c.max):
			continue
		if c.start_day != "" and _day < clock.day_of(c.start_day):
			continue
		var a: NpcAgent = npcs.get(c.a)
		var b: NpcAgent = npcs.get(c.b)
		if a == null or b == null or a.facility != b.facility:
			continue
		if c.place != "" and a.facility != c.place:
			continue
		if not (_can_chat(a, m) and _can_chat(b, m)):
			continue
		counters.chat += 1
		var key := "chat_%d" % counters.chat
		chats.append({"key": key, "conv": c.id, "a": a.id, "b": b.id, "facility": a.facility,
			"end": m + data.inum("chat_minutes", 30), "story": str(c.story) != ""})
		conv_counts[c.id] = int(conv_counts.get(c.id, 0)) + 1
		for n in [a, b]:
			n.state = NpcAgent.CHATTING
			n.chat_key = key
			npc_state_changed.emit(n.id)
		a.facing = 1 if b.pos.x > a.pos.x else -1
		b.facing = -a.facing


func _tick_chats(m: int) -> void:
	for ch in chats.duplicate():
		if m >= int(ch.end):
			_end_chat(ch, m)


func _end_chat(ch: Dictionary, m: int) -> void:
	chats.erase(ch)
	for id in [ch.a, ch.b]:
		var n: NpcAgent = npcs.get(id)
		if n == null:
			continue
		n.chat_key = ""
		n.last_chat = m
		if n.state == NpcAgent.CHATTING:
			n.state = NpcAgent.STAYING
		n.need_think = true
		npc_state_changed.emit(n.id)


func _end_chat_of(n: NpcAgent, m: int) -> void:
	for ch in chats:
		if ch.key == n.chat_key:
			_end_chat(ch, m)
			return
	n.chat_key = ""
	if n.state == NpcAgent.CHATTING:
		n.state = NpcAgent.STAYING


func chat_by_key(key: String) -> Dictionary:
	for ch in chats:
		if ch.key == key:
			return ch
	return {}


## 말풍선 클릭 → 엿듣기. {lines, story, conv, title}
func overhear(key: String) -> Dictionary:
	var ch := chat_by_key(key)
	if ch.is_empty():
		return {}
	var c := {}
	for cv in data.conversations:
		if cv.id == ch.conv:
			c = cv
	if c.is_empty():
		return {}
	heard[c.id] = int(heard.get(c.id, 0)) + 1
	if str(c.story) != "" and not story_seen.has(c.story):
		story_seen[c.story] = clock.label(_minute)
		_log("엿듣기로 스토리 대화 발견 (%s)" % c.story)
	return {"lines": data.dialogues.get(c.dialogue, []), "story": str(c.story), "conv": c.id,
		"title": "%s · %s 의 대화" % [data.npc_name(ch.a), data.npc_name(ch.b)], "cutscene": _take_cutscene("overhear", c.id)}


## 플레이어 직접 이동: 선택한 대원을 그 방의 그 위치(x, 없으면 자리)로. run = 뛰기 (이미 그쪽으로 걷는 중이면 뛰기로만 바꿈).
## 도착하면 그 방에 머묾 → 우클릭으로 행동 지시. 다음 일정 블록이 시작되면 일정으로 복귀. {ok, msg}
func issue_move(npc_id: String, fid: String, x: float = NAN, run: bool = false) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	if not data.facilities.has(fid):
		return _fail("갈 곳을 클릭하세요")
	if not unlocked.has(fid):
		return _fail("%s 은(는) 잠겨 있습니다 (먼저 해금)" % data.facility_name(fid))
	if not n.is_free():
		return _fail("%s 은(는) 지금 %s — 우클릭 → '지시 그만두기' 후 보낼 수 있습니다" % [n.name, n.state_name()])
	var r := data.facility_rect(fid)
	var tx := clampf(x, r.position.x + 30.0, r.end.x - 30.0) if not is_nan(x) else NAN
	if n.is_holding() and n.state == NpcAgent.MOVING and str(n.command.target) == fid and (is_nan(tx) or absf(tx - n.dest_x) < 40.0):
		if run and not n.running:
			n.running = true
			npc_state_changed.emit(n.id)
			return {"ok": true, "msg": "%s 이(가) %s 로 뛰어갑니다" % [n.name, data.facility_name(fid)]}
		return {"ok": true, "msg": ""}
	if not reachable(n.facility, fid):
		return _fail("%s 에서 %s 까지 갈 수 있는 길이 없습니다 (잠긴 방)" % [data.facility_name(n.facility), data.facility_name(fid)])
	if n.state == NpcAgent.CHATTING:
		_end_chat_of(n, _minute)
	n.command = {"type": "move", "target": fid, "activity": "idle", "issuer": "player"}
	n.activity = "idle"
	if not _go(n, fid, "", tx):
		n.command = {}
		return _fail(n.dest_reason)
	n.running = run
	return {"ok": true, "msg": "%s 이(가) %s 로 %s" % [n.name, data.facility_name(fid), "뛰어갑니다" if run else "갑니다"]}


## 지금 있는 방에서 할 수 있는 행동 (우클릭 메뉴) — [{id, label, enabled, why}]
func room_actions(npc_id: String) -> Array:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return []
	var fid := n.facility
	var tag := str(data.facilities.get(fid, {}).get("tag", ""))
	var free := n.is_free() and n.state != NpcAgent.MOVING
	var out: Array = []
	var kinds: Array = data.objects_in(fid).map(func(o): return str(data.objects[o].kind))
	if kinds.has("침대") or kinds.has("소파") or kinds.has("의무침대"):
		out.append({"id": "sleep", "label": "잠자기 (피로 회복)", "enabled": free and _pick_seat(n, fid, "sleep") != "", "why": "빈 자리 없음"})
	if not kinds.is_empty() or tag in ["공용", "생활"]:
		out.append({"id": "rest", "label": "쉬기", "enabled": free, "why": ""})
	if tag == "식당":
		out.append({"id": "eat", "label": "식사 (식재료 %d끼)" % food, "enabled": free, "why": ""})
	if tag == "연구" and is_researcher(npc_id):
		out.append({"id": "research", "label": "무기 연구", "enabled": true, "why": ""})
	if tag == "훈련" and is_combatant(n):
		out.append({"id": "train", "label": "훈련 (%d분, 전투 HP +%d)" % [data.inum("train_minutes", 120), data.inum("train_hp_bonus", 5)], "enabled": free, "why": ""})
	if tag == "의무":
		var cs := cstate(n)
		var need := not (cs.statuses as Array).is_empty() or float(cs.hp) < char_max_hp(ckey(n))
		out.append({"id": "medical", "label": "치료·휴식", "enabled": free and need, "why": "다친 데 없음"})
	var here_jobs := available_contracts().filter(func(c): return str(data.jobs[c].place) == fid)
	if tag in ["행정", "출입"] or not here_jobs.is_empty():
		out.append({"id": "jobs", "label": "업무·의뢰 맡기기", "enabled": free, "why": ""})
	if tag in ["무기고", "작업"]:
		out.append({"id": "facility", "label": "무기고 열기 (장착·강화)", "enabled": true, "why": ""})
	if tag == "상점":
		out.append({"id": "facility", "label": "PX 열기 (선물 구매)", "enabled": true, "why": ""})
	return out


## 지금 있는 방에서 행동: sleep / rest / eat — 그 방 자리로 가서 그 행동, 다음 일정 블록까지
func issue_activity(npc_id: String, activity: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	if not n.is_free() or n.state == NpcAgent.MOVING:
		return _fail("%s 은(는) 지금 %s" % [n.name, n.state_name()])
	var fid := n.facility
	var seat := _pick_seat(n, fid, activity)
	if activity == "sleep" and seat == "":
		return _fail("%s 에는 잘 자리가 없습니다" % data.facility_name(fid))
	if n.state == NpcAgent.CHATTING:
		_end_chat_of(n, _minute)
	n.command = {"type": "move", "target": fid, "activity": activity, "issuer": "player"}
	n.activity = activity
	if seat != "":
		if not _go(n, fid, seat):
			n.command = {}
			return _fail(n.dest_reason)
	else:
		n.dest = fid
		n.state = NpcAgent.STAYING
		npc_state_changed.emit(n.id)
	var what: String = {"sleep": "잠을 잡니다", "rest": "쉽니다", "eat": "식사합니다"}.get(activity, activity)
	var msg := "%s 이(가) %s 에서 %s" % [n.name, data.facility_name(fid), what]
	_log(msg)
	return {"ok": true, "msg": msg}


## 지시 그만두기 → 지금 일정으로 (진행 중인 작업·의뢰는 취소, 보상 없음)
func cancel_command(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null or n.command.is_empty():
		return _fail("그만둘 지시가 없습니다")
	if n.state == NpcAgent.UNAVAILABLE:
		return _fail("%s 은(는) 기지 밖에 있습니다" % n.name)
	var c := n.command
	if str(c.type) == "job":
		var job := _job(str(c.uid))
		if not job.is_empty():
			jobs.erase(job)
		claimed_contracts.erase(str(c.contract))
	n.command = {}
	n.busy = 0.0
	n.running = false
	_release_seat(n)
	if n.state != NpcAgent.MOVING:
		n.state = NpcAgent.STAYING
	n.need_think = true
	npc_state_changed.emit(n.id)
	_log("%s: 지시 취소 — 일정대로 움직입니다" % n.name)
	return {"ok": true, "msg": "%s: 지시 취소 — 일정대로 움직입니다" % n.name}


# ================================================================ 업무 · 외부 의뢰 · 훈련
func available_contracts() -> Array[String]:
	var out: Array[String] = []
	for cid in data.job_order:
		var j: Dictionary = data.jobs[cid]
		if not (j.initial or opened_contracts.has(cid)):
			continue
		if not j.repeat and claimed_contracts.has(cid):
			continue
		out.append(cid)
	return out


func _job(uid: String) -> Dictionary:
	for j in jobs:
		if j.uid == uid:
			return j
	return {}


func issue_job(npc_id: String, cid: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	if not (cid in available_contracts()):
		return _fail("수락할 수 없는 의뢰입니다 (이미 맡았거나 아직 열리지 않음)")
	if not n.is_free():
		return _fail("%s 은(는) 지금 다른 일을 하고 있습니다 (%s)" % [n.name, n.state_name()])
	var j: Dictionary = data.jobs[cid]
	if not unlocked.has(j.place):
		return _fail("%s 이(가) 잠겨 있습니다" % data.facility_name(j.place))
	if not reachable(n.facility, j.place):
		return _fail("%s 까지 갈 수 있는 길이 없습니다" % data.facility_name(j.place))
	counters.job += 1
	var uid := "job_%d" % counters.job
	jobs.append({"uid": uid, "contract": cid, "npc": npc_id, "state": "assigned", "minute": _minute})
	if not j.repeat:
		claimed_contracts[cid] = true
	_start_command(n, {"type": "job", "target": j.place, "uid": uid, "contract": cid, "issuer": "player"})
	var msg := "%s → %s (%d분, 보상 $%d 은 결산 때)" % [n.name, j.name, j.minutes, j.reward]
	_log(msg)
	return {"ok": true, "msg": msg, "uid": uid}


func _complete_job(uid: String, n: NpcAgent) -> void:
	var job := _job(uid)
	if job.is_empty() or job.state == "done":
		return
	job.state = "done"
	var j: Dictionary = data.jobs.get(job.contract, {})
	var amount := int(j.get("reward", 0))
	ledger.add_pending("job:" + uid, "contract" if j.get("kind", "") == "external" else "task", amount, str(job.contract),
		"%s (%s)" % [j.get("name", job.contract), n.name], week_now())
	_log("%s 완료 — $%d 은 이번 주 결산 때 지급" % [j.get("name", job.contract), amount])
	job_completed.emit(job)
	check_divine()   # 미션(의뢰) 완료 조건


func training_facility() -> String:
	for fid in data.facilities_with_tag("훈련"):
		if unlocked.has(fid):
			return fid
	return ""


func issue_train(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	if not is_combatant(n):
		return _fail("%s 은(는) 전투원이 아니라 훈련하지 않습니다" % n.name)
	var fid := training_facility()
	if fid == "":
		return _fail("훈련실이 잠겨 있습니다 (먼저 해금)")
	if not n.is_free():
		return _fail("%s 은(는) 지금 다른 일을 하고 있습니다 (%s)" % [n.name, n.state_name()])
	if not reachable(n.facility, fid):
		return _fail("훈련실까지 갈 수 있는 길이 없습니다")
	_start_command(n, {"type": "train", "target": fid, "issuer": "player"})
	var msg := "%s 이(가) 훈련하러 갑니다 (%d분)" % [n.name, data.inum("train_minutes", 120)]
	_log(msg)
	return {"ok": true, "msg": msg}


func training_level(character_id: String) -> int:
	return int(progression.get(character_id, {}).get("training", 0))


# ================================================================ 레벨 · 경험치 · 스킬 트리
## 전투에 나간 대원은 경험치를 받고 (승리 xp_win / 패배 xp_lose), 레벨이 오르면 스킬 포인트 +1.
## 스킬 트리 (밸런스 엑셀 '스킬트리'): 십자형 — 중앙(처음부터) + 동서남북 갈래 1~3단계. 갈래 끝(가장 높은 단계)은 한 캐릭터에 하나만.
func _prog(cid: String) -> Dictionary:
	if not progression.has(cid):
		progression[cid] = {"training": 0}
	var p: Dictionary = progression[cid]
	if not p.has("level"):
		p.level = start_level(cid)
		p.xp = 0
		p.skills = []
	if not p.has("faith"):
		p.faith = int(battle.char_faith.get(cid, {}).get("faith", 0)) if battle != null else 0
		p.faith_skills = []
	if not p.has("miracles"):
		p.miracles = []
	return p


func start_level(cid: String) -> int:
	if battle != null:
		var u: UnitData = GameData._find(battle.allies, cid)
		if u != null:
			return u.level
	return 1


func char_level(cid: String) -> int:
	return int(_prog(cid).level)


func char_xp(cid: String) -> int:
	return int(_prog(cid).xp)


## 다음 레벨까지 필요한 경험치 (이 레벨에서)
func xp_need(cid: String) -> int:
	return data.inum("xp_level_base", 100) + data.inum("xp_level_step", 50) * maxi(0, char_level(cid) - start_level(cid))


func level_max() -> int:
	return data.inum("level_max", 20)


## 경험치 더하기 → 오른 레벨 수
func add_xp(cid: String, amount: int) -> int:
	var p := _prog(cid)
	var ups := 0
	p.xp = int(p.xp) + maxi(0, amount)
	while int(p.level) < level_max() and int(p.xp) >= xp_need(cid):
		p.xp = int(p.xp) - xp_need(cid)
		p.level = int(p.level) + 1
		ups += 1
		_log("%s 레벨 업! Lv%d — 스킬 포인트 +1 (스킬 창에서 배우기)" % [_char_label(cid), p.level])
		leveled_up.emit(cid, int(p.level))
	if int(p.level) >= level_max():
		p.xp = 0
	check_divine()
	return ups


## kind = "active" / "passive" 면 그 트리만, "" 면 둘 다
func tree_nodes(cid: String, kind: String = "") -> Array:
	var all: Array = battle.skill_tree.get(cid, []) if battle != null else []
	return all if kind == "" else all.filter(func(n): return n.kind == kind)


func tree_node(cid: String, nid: String) -> Dictionary:
	for n in tree_nodes(cid):
		if n.id == nid:
			return n
	return {}


## 배운 노드 (각 트리의 시작 노드는 처음부터)
func learned_skills(cid: String) -> Array:
	var out: Array = (_prog(cid).skills as Array).duplicate()
	for n in tree_nodes(cid):
		if bool(n.start) and not out.has(n.id):
			out.push_front(n.id)
	return out


func has_skill(cid: String, nid: String) -> bool:
	return learned_skills(cid).has(nid)


## 스킬 포인트 (액티브·패시브 트리 공용) = 처음 1 + 오른 레벨 수 - 배운 (시작 노드 제외) 노드 수
func skill_points(cid: String) -> int:
	var used := (_prog(cid).skills as Array).filter(func(id):
		var n := tree_node(cid, str(id))
		return not n.is_empty() and not bool(n.start)).size()
	return 1 + char_level(cid) - start_level(cid) - used


## 노드 상태: learned 배움 / ready 배울 수 있음 / no_level 경험 부족 / need_prev 선행 필요 / no_point 포인트 부족 / capped 같은 택일 그룹의 다른 노드를 이미 배움
func skill_state(cid: String, nid: String) -> String:
	var n := tree_node(cid, nid)
	if n.is_empty():
		return ""
	if has_skill(cid, nid):
		return "learned"
	if char_level(cid) < int(n.level):
		return "no_level"
	if not prereq_met(cid, n):
		return "need_prev"
	if str(n.group) != "":
		for o in tree_nodes(cid, n.kind):
			if o.id != n.id and str(o.group) == str(n.group) and has_skill(cid, o.id):
				return "capped"
	if skill_points(cid) <= 0:
		return "no_point"
	return "ready"


## 선행을 채웠나 — req_all = 모두 / 아니면 하나라도 (선행이 없으면 바로)
func prereq_met(cid: String, n: Dictionary) -> bool:
	var reqs: Array = (n.get("req", []) as Array).filter(func(q): return not tree_node(cid, str(q)).is_empty())
	if reqs.is_empty():
		return true
	if bool(n.get("req_all", false)):
		return reqs.all(func(q): return has_skill(cid, str(q)))
	return reqs.any(func(q): return has_skill(cid, str(q)))


const SKILL_STATE_MSG := {"no_level": "경험 부족", "need_prev": "선행 스킬을 먼저 배워야 합니다", "no_point": "스킬 포인트가 없습니다",
	"capped": "택일 — 같은 그룹의 다른 스킬을 이미 배웠습니다", "learned": "이미 배웠습니다"}


func learn_skill(cid: String, nid: String) -> Dictionary:
	var st := skill_state(cid, nid)
	if st == "":
		return _fail("없는 스킬")
	if st != "ready":
		return _fail(SKILL_STATE_MSG.get(st, st))
	(_prog(cid).skills as Array).append(nid)
	var n := tree_node(cid, nid)
	_log("%s 스킬 습득: %s" % [_char_label(cid), n.name])
	return {"ok": true, "msg": "%s — %s 습득" % [_char_label(cid), n.name]}


## 배운 스킬 되돌리기 (포인트 돌려받음) [임시: 무료]. kind = "active" / "passive" 면 그 트리만, "" 면 전부
func reset_skills(cid: String, kind: String = "") -> Dictionary:
	var p := _prog(cid)
	var keep := (p.skills as Array).filter(func(id): return kind != "" and str(tree_node(cid, str(id)).get("kind", "")) != kind)
	if keep.size() == (p.skills as Array).size():
		return _fail("되돌릴 스킬이 없습니다")
	p.skills = keep
	var what := "%s 스킬" % TREE_KIND_NAME.get(kind, "") if kind != "" else "스킬"
	_log("%s %s 초기화" % [_char_label(cid), what])
	return {"ok": true, "msg": "%s %s 초기화 — 포인트를 돌려받았습니다" % [_char_label(cid), what]}


const TREE_KIND_NAME := {"active": "액티브", "passive": "패시브"}


# ---------------------------------------------------------------- 신앙 [임시 데이터]: 믿는 신에 따라 배울 수 있는 신앙 스킬이 다름
func god_of(cid: String) -> String:
	return str(battle.char_faith.get(cid, {}).get("god", "")) if battle != null else ""


func god_info(cid: String) -> Dictionary:
	return battle.gods.get(god_of(cid), {}) if battle != null else {}


func faith(cid: String) -> int:
	return int(_prog(cid).faith)


func faith_max() -> int:
	return 100


## 신앙도 올리기 (퀘스트 보상 · 컷씬 행동 · 요청 수락 — 전투 출전으로는 안 오름).
## 믿는 신이 없으면(무신앙) 안 쌓이고, 정체가 신이면 신앙도 대신 의지. 반환 = 실제로 바뀐 양. why = 기록에 남길 까닭
func add_faith(cid: String, v: int, why: String = "") -> int:
	if battle == null or is_divine(cid):
		return 0   # 신은 신앙 스킬 대신 기적 (의지)
	var g := god_of(cid)
	if g == "":
		return 0   # 무신앙: 신앙도가 쌓이지 않음
	var p := _prog(cid)
	var before := int(p.faith)
	p.faith = clampi(before + v, 0, faith_max())
	var gained := int(p.faith) - before
	if gained != 0 and why != "":
		_log("%s 신앙도 %+d → %d (%s)" % [_char_label(cid), gained, int(p.faith), why])
	check_divine()
	for fs in battle.faith_skills.get(g, []):
		if before < int(fs.need) and int(p.faith) >= int(fs.need):
			_log("%s 신앙도 %d — 신앙 스킬 '%s' 을(를) 배울 수 있습니다" % [_char_label(cid), p.faith, fs.name])
	return gained


## 믿는 신이 없나 (무신앙 — 신 해금으로 정체가 드러난 신은 아님)
func faithless(cid: String) -> bool:
	return god_of(cid) == "" and not is_divine(cid)


## 신앙도 보상 결과 글 ("하나 신앙도 +5" / "키라 — 믿음이 없어 신앙도가 쌓이지 않음")
func _faith_text(cid: String, gained: int, want: int) -> String:
	if is_divine(cid):
		return "%s — 신이라 신앙도 대신 의지" % _char_label(cid)
	if god_of(cid) == "":
		return "%s — 믿음이 없어 신앙도가 쌓이지 않음" % _char_label(cid)
	return "%s 신앙도 %+d" % [_char_label(cid), gained if gained != 0 else want]


## 이 캐릭터가 믿는 신의 신앙 스킬 (필요 신앙도 순)
func faith_skill_list(cid: String) -> Array:
	return battle.faith_skills.get(god_of(cid), []) if battle != null else []


func faith_skill(cid: String, sid: String) -> Dictionary:
	for fs in faith_skill_list(cid):
		if fs.id == sid:
			return fs
	return {}


func has_faith_skill(cid: String, sid: String) -> bool:
	return (_prog(cid).faith_skills as Array).has(sid)


## learned 배움 / ready 배울 수 있음 / no_faith 신앙 부족 / other_god 다른 신의 스킬
func faith_state(cid: String, sid: String) -> String:
	var fs := faith_skill(cid, sid)
	if fs.is_empty():
		return "other_god"
	if has_faith_skill(cid, sid):
		return "learned"
	if faith(cid) < int(fs.need):
		return "no_faith"
	return "ready"


func learn_faith_skill(cid: String, sid: String) -> Dictionary:
	match faith_state(cid, sid):
		"other_god":
			return _fail("믿는 신의 스킬이 아닙니다")
		"learned":
			return _fail("이미 배웠습니다")
		"no_faith":
			return _fail("신앙 부족 — 신앙도 %d 필요" % int(faith_skill(cid, sid).need))
	(_prog(cid).faith_skills as Array).append(sid)
	var fs := faith_skill(cid, sid)
	_log("%s 신앙 스킬 습득: %s (%s)" % [_char_label(cid), fs.name, god_info(cid).get("name", "")])
	return {"ok": true, "msg": "%s — %s 습득" % [_char_label(cid), fs.name]}


# ---------------------------------------------------------------- 신 해금 캐릭터 · 기적 [임시 데이터]
## 정체가 신인 캐릭터: 해금 조건(UnlockCond)을 채우면 신앙 탭이 '기적' 으로 — 기적은 신앙도가 아니라 의지로 배움 (해금될 때 시작 의지, 출전마다 + will_battle)
func divine_info(cid: String) -> Dictionary:
	return battle.divine.get(cid, {}) if battle != null else {}


## "" = 신 해금 캐릭터 아님 / "locked" = 아직 잠김 / "unlocked" = 정체가 드러남
func divine_state(cid: String) -> String:
	var dv := divine_info(cid)
	if dv.is_empty():
		return ""
	return "unlocked" if bool(dv.get("unlocked", false)) or divine_unlocked.has(cid) or str(dv.condition.type) == "always" else "locked"


func is_divine(cid: String) -> bool:
	return divine_state(cid) == "unlocked"


## 정체인 신 정보 (gods 항목) — 신이 아니면 {}
func divine_god(cid: String) -> Dictionary:
	return battle.gods.get(str(divine_info(cid).get("god", "")), {}) if is_divine(cid) else {}


## 해금 조건을 채웠나 (UnlockCond: always · manual · quest(미션 완료) · level · faith · affinity · day)
func cond_met(c: Dictionary, cid: String) -> bool:
	var v := int(c.get("value", 0))
	match str(c.get("type", "manual")):
		"always":
			return true
		"level":
			return char_level(cid) >= v
		"faith":
			return faith(cid) >= v
		"affinity":
			return float(cstate_of(cid).get("affinity", 0.0)) >= v
		"day":
			return _day + 1 >= v
		"quest":
			return quest_done(str(c.get("target", "")))
	return false


## 미션 완료: "contract:id" = 그 의뢰 업무를 끝냄 / "stage:id" = 그 전투 승리 / "research:id" = 연구 완료 / "quest:id" = 퀘스트 완료
func quest_done(target: String) -> bool:
	var p := target.split(":")
	if p.size() < 2:
		return false
	var id := target.substr(p[0].length() + 1)
	match p[0]:
		"contract":
			return jobs.any(func(j): return str(j.get("contract", "")) == id and str(j.get("state", "")) == "done")
		"stage":
			return battle_history.any(func(b): return str(b.get("stage", "")) == id and str(b.get("winner", "")) == "ally")
		"research":
			return researched.has(id)
		"quest":
			return quest_status(id) == "done"
		"cutscene":
			return cutscenes_seen.has(id)
	return false


## 이벤트·대사·디버그에서 직접 해금. 반환 {ok, msg}
func unlock_divine(cid: String, why: String = "") -> Dictionary:
	if divine_state(cid) == "":
		return _fail("신 해금 캐릭터가 아닙니다")
	if is_divine(cid):
		return _fail("이미 해금")
	divine_unlocked[cid] = true
	var p := _prog(cid)
	if not p.has("will"):
		p.will = int(divine_info(cid).get("will", 0))
	var g: Dictionary = battle.gods.get(str(divine_info(cid).god), {})
	_log("✦ %s 의 정체 — %s! 신앙 탭이 '기적' 으로 바뀝니다%s" % [_char_label(cid), g.get("name", "신"), " (%s)" % why if why != "" else ""])
	divine_revealed.emit(cid)
	trigger_cutscenes("divine", cid)
	return {"ok": true, "msg": "%s — 정체는 %s" % [_char_label(cid), g.get("name", "신")]}


## 잠긴 신 해금 캐릭터 중 조건을 채운 캐릭터를 해금 (레벨·신앙도·친밀도가 바뀔 때, 날이 바뀔 때, 불러온 뒤)
func check_divine() -> void:
	if battle == null:
		return
	update_quests()
	for cid in battle.divine:
		if divine_state(cid) == "locked" and cond_met(battle.divine[cid].condition, cid):
			unlock_divine(cid, UnlockCond.describe(battle.divine[cid].condition, UnlockCond.mission_names(data, battle)))


# ---------------------------------------------------------------- 퀘스트 (data/quests.json — 에디터 '퀘스트' 탭) [임시 데이터]
## 시작 조건을 채우면 자동 시작 (직접 시작은 start_quest) → 단계를 앞에서부터 하나씩 → 마지막 단계면 완료 + 보상 (현금은 주간 결산 때, 친밀도는 의뢰인)
func quest_defs() -> Array:
	return battle.quests if battle != null else []


func quest_def(qid: String) -> Dictionary:
	for q in quest_defs():
		if q.id == qid:
			return q
	return {}


## "" = 아직 시작 안 함 / "active" = 진행 중 / "done" = 완료
func quest_status(qid: String) -> String:
	return str(quests.get(qid, {}).get("state", ""))


## 의뢰인 대원의 전투 캐릭터 id (시작 조건 레벨·신앙도·친밀도용)
func _giver_char(q: Dictionary) -> String:
	return str(data.npcs.get(str(q.get("giver", "")), {}).get("character_id", ""))


## 이벤트·대사·디버그에서 직접 시작. 반환 {ok, msg}
func start_quest(qid: String) -> Dictionary:
	var q := quest_def(qid)
	if q.is_empty():
		return _fail("없는 퀘스트")
	if quest_status(qid) != "":
		return _fail("이미 시작한 퀘스트")
	quests[qid] = {"state": "active", "step": 0, "base": 0, "started": _day + 1, "finished": -1}
	_begin_step(q)
	_log("◆ 퀘스트 시작: %s" % q.name)
	quest_started.emit(qid)
	_quest_cutscenes("quest_start", qid, 0)
	update_quests()
	return {"ok": true, "msg": "퀘스트 시작 — %s" % q.name}


## 횟수 단계의 지금까지 횟수 (의뢰 완료 · 전투 승리 · 대화)
func _step_count(st: Dictionary) -> int:
	var t := str(st.target)
	match str(st.kind):
		"contract":
			return jobs.filter(func(j): return str(j.get("contract", "")) == t and str(j.get("state", "")) == "done").size()
		"stage":
			return battle_history.filter(func(b): return str(b.get("winner", "")) == "ally" and (t == "" or str(b.get("stage", "")) == t)).size()
		"talk":
			return int(talk_counts.get(t, 0))
	return 0


func _begin_step(q: Dictionary) -> void:
	var qs: Dictionary = quests[q.id]
	var steps: Array = q.steps
	qs.base = _step_count(steps[qs.step]) if int(qs.step) < steps.size() else 0


## 지금 단계 진행 {step(0부터), total, have, need, done(이 단계를 채움)}
func quest_progress(qid: String) -> Dictionary:
	var q := quest_def(qid)
	var qs: Dictionary = quests.get(qid, {})
	if q.is_empty() or qs.is_empty():
		return {}
	var steps: Array = q.steps
	var i := int(qs.step)
	if qs.state == "done" or i >= steps.size():
		return {"step": steps.size(), "total": steps.size(), "have": 1, "need": 1, "done": true}
	var st: Dictionary = steps[i]
	var t := str(st.target)
	var n := int(st.count)
	var have := 0
	var need := 1
	match str(st.kind):
		"contract", "stage", "talk":
			have = _step_count(st) - int(qs.base)
			need = n
		"research":
			have = 1 if researched.has(t) else 0
		"affinity":
			have = int(cstate(npcs[t]).get("affinity", 0.0)) if npcs.has(t) else 0
			need = n
		"level":
			have = char_level(t)
			need = n
		"day":
			have = _day + 1
			need = n
		"quest":
			have = 1 if quest_status(t) == "done" else 0
		"cutscene":
			have = 1 if cutscenes_seen.has(t) else 0
	return {"step": i, "total": steps.size(), "have": mini(have, need), "need": need, "done": have >= need}


## 시작 조건을 채운 퀘스트 시작 · 채운 단계 넘기기 · 완료 (check_divine 에서 — 레벨·신앙도·친밀도·날·의뢰·연구·전투·대화가 바뀔 때)
func update_quests() -> void:
	if _questing or battle == null:
		return
	_questing = true
	var changed := true
	while changed:
		changed = false
		for q in quest_defs():
			var qid: String = q.id
			var stt := quest_status(qid)
			if stt == "" and q.start.type != "manual" and cond_met(q.start, _giver_char(q)):
				quests[qid] = {"state": "active", "step": 0, "base": 0, "started": _day + 1, "finished": -1}
				_begin_step(q)
				_log("◆ 퀘스트 시작: %s" % q.name)
				quest_started.emit(qid)
				_quest_cutscenes("quest_start", qid, 0)
				changed = true
			elif stt == "active" and quest_progress(qid).get("done", false):
				var qs: Dictionary = quests[qid]
				qs.step = int(qs.step) + 1
				changed = true
				if int(qs.step) >= (q.steps as Array).size():
					_complete_quest(q)
				else:
					_begin_step(q)
					quest_step.emit(qid, int(qs.step))
					trigger_cutscenes("quest_step", qid, int(qs.step) + 1)
	_questing = false


## 퀘스트 신앙도 보상을 받는 전투 캐릭터 ("" = 없음) — faith_char 가 비면 의뢰인
func quest_faith_char(q: Dictionary) -> String:
	var fc := str(q.get("rewards", {}).get("faith_char", ""))
	return fc if fc != "" else _giver_char(q)


func _complete_quest(q: Dictionary) -> void:
	var qs: Dictionary = quests[q.id]
	qs.state = "done"
	qs.finished = _day + 1
	var rw: Dictionary = q.rewards
	var got := PackedStringArray()
	if int(rw.cash) > 0:
		ledger.add_pending("quest:" + q.id, "quest", int(rw.cash), q.id, "퀘스트 보상 (%s)" % q.name, week_now())
		got.append("$%d (주간 결산)" % int(rw.cash))
	var giver: NpcAgent = npcs.get(str(q.giver))
	if int(rw.affinity) != 0 and giver != null:
		_add_affinity(giver, float(rw.affinity))
		got.append("%s 친밀도 %+d" % [giver.name, int(rw.affinity)])
	var fc := quest_faith_char(q)
	if int(rw.get("faith", 0)) != 0 and fc != "":
		got.append(_faith_text(fc, add_faith(fc, int(rw.faith), "퀘스트 '%s'" % q.name), int(rw.faith)))
	_log("◆ 퀘스트 완료: %s%s" % [q.name, " — 보상 " + ", ".join(got) if not got.is_empty() else ""])
	quest_completed.emit(q.id)
	trigger_cutscenes("quest_done", q.id)


# ---------------------------------------------------------------- 컷씬 (data/cutscenes.json — 에디터 '컷씬' 탭) [임시 데이터]
## 계기(새 게임 · 퀘스트 시작/단계/완료 · 말 걸기 · 엿듣기 · n일차 · 신 정체 · 전투 승리)가 오면 대기열에 넣고, 기지 HUD 가 창이 없을 때 차례로 재생.
## 말 걸기·엿듣기 컷씬은 대기열이 아니라 그 대화 대신 바로 (begin_dialogue · overhear 결과의 "cutscene").
func cutscene_defs() -> Array:
	return battle.cutscenes if battle != null else []


func cutscene_def(id: String) -> Dictionary:
	for c in cutscene_defs():
		if c.id == id:
			return c
	return {}


func _cutscene_matches(c: Dictionary, type: String, target: String, value: int) -> bool:
	var t: Dictionary = c.trigger
	if str(t.type) != type:
		return false
	if type in ["quest_start", "quest_done", "quest_step", "talk", "overhear", "divine"] and str(t.target) != target:
		return false
	if type == "battle_win" and str(t.target) != "" and str(t.target) != target:
		return false
	if type in ["quest_step", "day"] and int(t.value) != value:
		return false
	return not (bool(c.once) and cutscenes_seen.has(c.id))


## 계기가 맞는 컷씬을 대기열에 (한 번만 컷씬은 이미 봤거나 대기 중이면 빼고)
func trigger_cutscenes(type: String, target: String = "", value: int = 0) -> void:
	for c in cutscene_defs():
		if _cutscene_matches(c, type, target, value) and not cutscene_queue.has(c.id):
			cutscene_queue.append(c.id)
			cutscene_queued.emit(c.id)


func _quest_cutscenes(type: String, qid: String, _step: int) -> void:
	trigger_cutscenes(type, qid)
	trigger_cutscenes("quest_step", qid, 1)   # 1단계 시작 = 퀘스트 시작


## 말 걸기·엿듣기: 맞는 컷씬 하나 (없으면 "")
func _take_cutscene(type: String, target: String) -> String:
	for c in cutscene_defs():
		if _cutscene_matches(c, type, target, 0):
			return str(c.id)
	return ""


## 이벤트·스크립트에서 직접 재생 예약
func queue_cutscene(id: String) -> bool:
	if cutscene_def(id).is_empty() or cutscene_queue.has(id):
		return false
	cutscene_queue.append(id)
	cutscene_queued.emit(id)
	return true


## 다음에 재생할 컷씬 id ("" = 없음) — 꺼내면 대기열에서 빠짐
func next_cutscene() -> String:
	while not cutscene_queue.is_empty():
		var id := str(cutscene_queue.pop_front())
		if not cutscene_def(id).is_empty():
			return id
	return ""


## 컷씬을 보기 시작함 (재생 화면이 이어진 컷씬마다 부름)
func mark_cutscene_seen(id: String) -> void:
	if not cutscenes_seen.has(id):
		cutscenes_seen[id] = _day + 1
		_log("▶ 컷씬: %s" % cutscene_def(id).get("name", id))
	cutscene_queue.erase(id)
	check_divine()   # 퀘스트 단계 '컷씬 보기' · 미션 'cutscene:id'


## 행동 컷. 반환 {ok, msg}
func apply_cutscene_action(st: Dictionary) -> Dictionary:
	var t := str(st.get("target", ""))
	var v := int(st.get("value", 0))
	match str(st.get("do", "")):
		"start_quest":
			return start_quest(t)
		"unlock_divine":
			return unlock_divine(t, "컷씬")
		"affinity":
			var n: NpcAgent = npcs.get(t)
			if n == null:
				return _fail("없는 대원")
			_add_affinity(n, float(v))
			return {"ok": true, "msg": "%s 친밀도 %+d" % [n.name, v]}
		"faith":
			var fn: NpcAgent = npcs.get(t)
			if fn == null or fn.character_id == "":
				return _fail("전투 캐릭터가 아닌 대원")
			var gained := add_faith(fn.character_id, v, "이벤트")
			return {"ok": gained != 0, "msg": _faith_text(fn.character_id, gained, v)}
		"cash":
			var key := "cutscene:%s:%d" % [t, _minute]
			ledger.add_pending(key, "event", v, t, "이벤트 (%s)" % (t if t != "" else "컷씬"), week_now())
			return {"ok": true, "msg": "$%d — 주간 결산 때" % v}
	return _fail("모르는 행동")


func miracle_list(cid: String) -> Array:
	return battle.miracles.get(cid, []) if battle != null else []


func miracle(cid: String, mid: String) -> Dictionary:
	for m in miracle_list(cid):
		if m.id == mid:
			return m
	return {}


## 의지 (신 캐릭터만, 기적을 배우는 데 씀): 해금될 때 divine.will, 출전마다 + will_battle
func will(cid: String) -> int:
	var p := _prog(cid)
	return int(p.get("will", divine_info(cid).get("will", 0)))


func will_max() -> int:
	return FaithData.FAITH_MAX


func add_will(cid: String, v: int) -> void:
	if not is_divine(cid):
		return
	var p := _prog(cid)
	var before := will(cid)
	p.will = clampi(before + v, 0, will_max())
	for m in miracle_list(cid):
		if before < int(m.need) and int(p.will) >= int(m.need):
			_log("%s 의지 %d — 기적 '%s' 을(를) 일으킬 수 있습니다" % [_char_label(cid), p.will, m.name])


## learned 배움 / ready 배울 수 있음 / no_faith 의지 부족 / locked 정체가 아직 안 드러남 / other 그 캐릭터 기적 아님
func miracle_state(cid: String, mid: String) -> String:
	var m := miracle(cid, mid)
	if m.is_empty():
		return "other"
	if not is_divine(cid):
		return "locked"
	if (_prog(cid).miracles as Array).has(mid):
		return "learned"
	if will(cid) < int(m.need):
		return "no_faith"
	return "ready"


func learn_miracle(cid: String, mid: String) -> Dictionary:
	match miracle_state(cid, mid):
		"other":
			return _fail("이 캐릭터의 기적이 아닙니다")
		"locked":
			return _fail("아직 정체가 드러나지 않았습니다")
		"learned":
			return _fail("이미 배웠습니다")
		"no_faith":
			return _fail("의지 부족 — 의지 %d 필요" % int(miracle(cid, mid).need))
	(_prog(cid).miracles as Array).append(mid)
	var m := miracle(cid, mid)
	_log("%s 기적 습득: %s" % [_char_label(cid), m.name])
	return {"ok": true, "msg": "%s — 기적 %s" % [_char_label(cid), m.name]}


## 배운 스킬 트리 노드 + 신앙 스킬 (효과 계산용) [{effect, value}]
func _learned_effects(cid: String) -> Array:
	var out: Array = []
	for nid in learned_skills(cid):
		var n := tree_node(cid, nid)
		if not n.is_empty():
			out.append(n)
	for sid in _prog(cid).faith_skills:
		var fs := faith_skill(cid, str(sid))
		if not fs.is_empty():
			out.append(fs)
	if is_divine(cid):   # 기적 (정체가 드러난 뒤에만)
		for mid in _prog(cid).miracles:
			var m := miracle(cid, str(mid))
			if not m.is_empty():
				out.append(m)
	return out


## 배운 노드·신앙 스킬 효과를 전투용 복제본에
func _apply_skill_tree(copy: UnitData, cid: String) -> void:
	copy.power_bonus = 0
	copy.heal_bonus = 0
	copy.skill_power = {}
	for n in _learned_effects(cid):
		var v := int(n.value)
		var ef: String = n.effect
		match ef:
			"hp": copy.max_hp += v
			"speed": copy.speed += v
			"ap": copy.max_ap += v
			"ap_rec": copy.ap_recovery += v
			"defense": copy.defense += v
			"accuracy": copy.accuracy += v
			"evasion": copy.evasion = clampi(copy.evasion + v, 0, 95)
			"power": copy.power_bonus += v
			"heal": copy.heal_bonus += v
			_:
				if ef.begins_with("skill_power:"):
					var sid := ef.substr(12)
					copy.skill_power[sid] = int(copy.skill_power.get(sid, 0)) + v
				elif ef.begins_with("skill:"):
					var sid2 := ef.substr(6)
					if not copy.skill_ids.has(sid2):
						# 필살기 앞에 끼움 (전투 HUD 기본 스킬 칸 순서)
						var at := copy.skill_ids.find("ultimate")
						if at < 0:
							copy.skill_ids.append(sid2)
						else:
							copy.skill_ids.insert(at, sid2)


func _start_command(n: NpcAgent, cmd: Dictionary) -> void:
	if n.state == NpcAgent.CHATTING:
		_end_chat_of(n, _minute)
	n.command = cmd
	var seat := _pick_seat(n, str(cmd.target), "medical") if str(cmd.type) == "medical" else ""
	if not _go(n, str(cmd.target), seat):
		n.command = {}
		return
	npc_state_changed.emit(n.id)


func _finish_command(n: NpcAgent) -> void:
	var c := n.command
	match str(c.get("type", "")):
		"job":
			_complete_job(str(c.uid), n)
			if n.state == NpcAgent.UNAVAILABLE:
				_log("%s 이(가) 기지로 돌아왔습니다" % n.name)
		"train":
			var cid := n.character_id
			if not progression.has(cid):
				progression[cid] = {"training": 0}
			progression[cid].training = int(progression[cid].training) + 1
			_log("%s 훈련 완료 — 훈련 %d단계 (전투 최대 HP +%d)" % [n.name, progression[cid].training, progression[cid].training * data.inum("train_hp_bonus", 5)])
	n.command = {}
	n.busy = 0.0
	n.state = NpcAgent.STAYING
	n.dest = n.facility
	_release_seat(n)
	n.need_think = true   # 지시 완료 → 현재 요일·시각 일정으로 복귀
	npc_state_changed.emit(n.id)


# ================================================================ 작업실: 제작 · 강화
func workshop_facility() -> String:
	for fid in data.facilities_with_tag("무기고"):
		if unlocked.has(fid):
			return fid
	return ""


func item_name(item_id: String) -> String:
	if battle != null and battle.items.has(item_id):
		return str(battle.items[item_id].name)
	return item_id


func inv_item(uid: String) -> Dictionary:
	for it in inventory:
		if it.uid == uid:
			return it
	return {}


func start_craft(rid: String) -> Dictionary:
	if workshop_facility() == "":
		return _fail("무기고가 잠겨 있습니다")
	if not workshop.is_empty():
		return _fail("무기고가 다른 작업 중입니다")
	var r: Dictionary = data.recipes.get(rid, {})
	if r.is_empty():
		return _fail("없는 레시피")
	if not recipe_unlocked(rid):
		return _fail("연구가 필요합니다: %s" % data.research.get(recipe_research(rid), {}).get("name", ""))
	workshop = {"kind": "craft", "recipe": rid, "remaining": int(r.minutes), "total": int(r.minutes)}
	_log("제작 시작: %s (%d분)" % [r.name, r.minutes])
	return {"ok": true, "msg": "제작 시작: %s" % r.name}


func start_enhance(uid: String) -> Dictionary:
	if workshop_facility() == "":
		return _fail("무기고가 잠겨 있습니다")
	if not workshop.is_empty():
		return _fail("무기고가 다른 작업 중입니다")
	var it := inv_item(uid)
	if it.is_empty():
		return _fail("없는 무기")
	if int(it.plus) >= data.inum("enhance_max", 5):
		return _fail("최대 강화 단계입니다")
	var mins := data.inum("enhance_minutes", 60)
	workshop = {"kind": "enhance", "uid": uid, "remaining": mins, "total": mins}
	_log("강화 시작: %s +%d → +%d" % [item_name(it.item), it.plus, int(it.plus) + 1])
	return {"ok": true, "msg": "강화 시작: %s" % item_name(it.item)}


func _tick_workshop() -> void:
	if workshop.is_empty():
		return
	workshop.remaining = int(workshop.remaining) - 1
	if int(workshop.remaining) > 0:
		return
	var w := workshop
	workshop = {}
	if w.kind == "craft":
		var r: Dictionary = data.recipes.get(str(w.recipe), {})
		counters.inv += 1
		inventory.append({"uid": "w%d" % counters.inv, "item": str(r.get("item", "")), "plus": 0, "owner": "", "slot": -1})
		_log("제작 완료: %s → 무기고" % item_name(str(r.get("item", ""))))
	else:
		var it := inv_item(str(w.uid))
		if not it.is_empty():
			it.plus = int(it.plus) + 1
			_log("강화 완료: %s +%d" % [item_name(it.item), it.plus])


# ================================================================ 연구실 (로한): 연구 → 무기 제작 해금
func lab_facility() -> String:
	for fid in data.facilities_with_tag("연구"):
		if unlocked.has(fid):
			return fid
	return ""


func researcher_id() -> String:
	var id := data.text("researcher_npc", "")
	return id if npcs.has(id) else ""


func is_researcher(npc_id: String) -> bool:
	return npc_id != "" and npc_id == researcher_id()


## 이 제작 레시피를 해금하는 연구 id ("" = 처음부터 제작 가능)
func recipe_research(rid: String) -> String:
	for qid in data.research_order:
		if (data.research[qid].unlocks as Array).has(rid):
			return qid
	return ""


func recipe_unlocked(rid: String) -> bool:
	var q := recipe_research(rid)
	return q == "" or researched.has(q)


## 연구 상태: "done" 완료 / "active" 진행 중 / "locked" 선행 연구 필요 / "ready" 시작 가능
func research_state(qid: String) -> String:
	if researched.has(qid):
		return "done"
	if str(research.get("id", "")) == qid:
		return "active"
	var pre := str(data.research.get(qid, {}).get("prereq", ""))
	if pre != "" and not researched.has(pre):
		return "locked"
	return "ready"


## 연구가 지금 진행되는가: 연구원이 연구실에서 깨어 있음 (이동 중·잠·외출이면 멈춤). 이유 문자열 ("" = 진행)
func research_pause_reason() -> String:
	var rid := researcher_id()
	if rid == "":
		return "연구원이 없습니다"
	var n: NpcAgent = npcs[rid]
	var lab := lab_facility()
	if lab == "":
		return "연구실이 잠겨 있습니다"
	if n.facility != lab or n.state == NpcAgent.MOVING:
		return "%s — 연구실 밖" % n.name
	if n.activity == "sleep" or n.state in [NpcAgent.UNAVAILABLE, NpcAgent.TREATMENT, NpcAgent.RECOVERING]:
		return "%s — 쉬는 중" % n.name
	return ""


func start_research(qid: String) -> Dictionary:
	var q: Dictionary = data.research.get(qid, {})
	if q.is_empty():
		return _fail("없는 연구")
	if lab_facility() == "":
		return _fail("연구실이 잠겨 있습니다")
	match research_state(qid):
		"done":
			return _fail("이미 끝낸 연구입니다")
		"active":
			return _fail("이미 연구 중입니다")
		"locked":
			return _fail("먼저 '%s' 연구가 필요합니다" % data.research.get(q.prereq, {}).get("name", q.prereq))
	if not research.is_empty():
		return _fail("다른 연구가 진행 중입니다 (%s)" % data.research.get(str(research.id), {}).get("name", ""))
	var cost := int(q.cost)
	if ledger.cash < cost:
		return _fail("달러가 부족합니다 ($%d 더 필요)" % (cost - ledger.cash))
	counters["research"] = int(counters.get("research", 0)) + 1
	if cost > 0 and not ledger.post("research:%s:%d" % [qid, counters.research], _minute, clock.label(_minute), "research", -cost, qid, "%s 연구" % q.name, week_now()):
		return _fail("이미 처리된 연구 비용입니다")
	research = {"id": qid, "remaining": int(q.minutes), "total": int(q.minutes)}
	_log("연구 시작: %s (-$%d, %d분)" % [q.name, cost, q.minutes])
	return {"ok": true, "msg": "연구 시작: %s" % q.name}


func _tick_research() -> void:
	if research.is_empty() or research_pause_reason() != "":
		return
	research.remaining = int(research.remaining) - 1
	if int(research.remaining) > 0:
		return
	var qid := str(research.id)
	research = {}
	researched[qid] = true
	var q: Dictionary = data.research.get(qid, {})
	var made := PackedStringArray()
	for rid in q.get("unlocks", []):
		made.append(item_name(str(data.recipes.get(rid, {}).get("item", rid))))
	_log("연구 완료: %s → 무기고에서 %s 제작 가능" % [q.get("name", qid), ", ".join(made)])
	research_completed.emit(qid)
	check_divine()   # 미션(연구) 완료 조건


## 캐릭터의 장착 무기 (슬롯 순)
func weapons_of(character_id: String) -> Array:
	var out := inventory.filter(func(it): return it.owner == character_id)
	out.sort_custom(func(a, b): return int(a.slot) < int(b.slot))
	return out


## slot 0 = 주무기, 1·2 = 보조. uid "" = 해제 (주무기는 해제 불가)
func equip(character_id: String, slot: int, uid: String) -> Dictionary:
	var cur := {}
	for it in inventory:
		if it.owner == character_id and int(it.slot) == slot:
			cur = it
	if uid == "":
		if slot == 0:
			return _fail("주무기는 비울 수 없습니다")
		if not cur.is_empty():
			cur.owner = ""
			cur.slot = -1
		return {"ok": true, "msg": "해제"}
	var it := inv_item(uid)
	if it.is_empty():
		return _fail("없는 무기")
	if it.owner != "" and it.owner != character_id:
		return _fail("다른 대원이 쓰는 무기입니다")
	if not cur.is_empty() and cur != it:
		if it.owner == character_id:   # 같은 대원의 다른 칸 무기와 맞바꿈
			cur.slot = it.slot
		else:
			cur.owner = ""
			cur.slot = -1
	it.owner = character_id
	it.slot = slot
	return {"ok": true, "msg": "%s 장착" % item_name(it.item)}


## 전투 연계: 훈련·장비·강화를 아군 UnitData 복제본에 반영 (전투 규칙은 그대로, 수치 데이터만)
func apply_to_ally(copy: UnitData, base: UnitData) -> void:
	copy.max_hp = base.max_hp + training_level(base.id) * data.inum("train_hp_bonus", 5)
	copy.level = char_level(base.id)
	_apply_skill_tree(copy, base.id)
	var ws := weapons_of(base.id)
	if ws.is_empty() or battle == null:
		return
	var out: Array[Dictionary] = []
	for it in ws:
		var item: Dictionary = battle.items.get(str(it.item), {})
		if item.is_empty():
			continue
		var plus := int(it.plus)
		out.append({"id": str(it.item), "name": str(item.name) + (" +%d" % plus if plus > 0 else ""), "range_type": item.range_type,
			"power_bonus": int(item.power_bonus) + plus * data.inum("enhance_power_bonus", 1), "sprite": item.sprite})
	if not out.is_empty():
		copy.weapons = out


# ================================================================ 몸 상태 · 오브젝트 · 식사
## 대원 몸 상태 (전투 캐릭터 id 기준 — 전투와 기지가 같이 씀)
func cstate_of(character_id: String) -> Dictionary:
	if not chars.has(character_id):
		chars[character_id] = {"hp": float(char_max_hp(character_id)), "statuses": [], "fatigue": data.num("fatigue_start", 20.0),
			"affinity": data.num("affinity_start", 20.0), "talk_day": -1, "seen_talks": []}
	return chars[character_id]


func cstate(n: NpcAgent) -> Dictionary:
	return cstate_of(ckey(n))


## 몸 상태 키: 전투 캐릭터 id, 전투에 나가지 않는 대원(로한)은 대원 id
static func ckey(n: NpcAgent) -> String:
	return n.character_id if n.character_id != "" else n.id


func is_combatant(n: NpcAgent) -> bool:
	return n.character_id != ""


## 전투 최대 HP (훈련 반영)
func char_max_hp(character_id: String) -> int:
	var base_hp := 100
	if battle != null:
		var u: UnitData = GameData._find(battle.allies, character_id)
		if u != null:
			base_hp = u.max_hp
	var tree_hp := 0
	for n in _learned_effects(character_id):
		if str(n.get("effect", "")) == "hp":
			tree_hp += int(n.value)
	return base_hp + training_level(character_id) * data.inum("train_hp_bonus", 5) + tree_hp


func _add_affinity(n: NpcAgent, v: float) -> void:
	var cs := cstate(n)
	var before := float(cs.affinity)
	cs.affinity = clampf(before + v, 0.0, 100.0)
	check_divine()
	for t in data.affinity_talks.get(n.id, []):
		if before < float(t.need) and float(cs.affinity) >= float(t.need):
			_log("%s 친밀도 %d — 새 대화 해금! (클릭해서 대화)" % [n.name, int(t.need)])
			npc_state_changed.emit(n.id)


## 매 분: 잠은 오브젝트 위에서만 피로 회복(오브젝트마다 다름), 체력은 체력회복 오브젝트(의무침대)에서만, 깨어 있으면 피로 증가
func _tick_body(n: NpcAgent) -> void:
	var cs := cstate(n)
	var per := 1.0 / 60.0
	var o: Dictionary = data.objects.get(n.seat, {}) if n.seat != "" and n.state != NpcAgent.MOVING else {}
	var asleep := (n.state == NpcAgent.STAYING and n.activity == "sleep") or n.state == NpcAgent.RECOVERING
	if asleep:
		if not o.is_empty():
			cs.fatigue = float(cs.fatigue) - float(o.fatigue_rate) * per
			if float(o.hp_rate) > 0.0:
				cs.hp = minf(float(char_max_hp(ckey(n))), float(cs.hp) + float(o.hp_rate) * per)
	else:
		var rate := data.num("fatigue_awake_per_hour", 2.0)
		if n.state in [NpcAgent.CLEANING, NpcAgent.ASSIGNED_WORK, NpcAgent.UNAVAILABLE]:
			rate = data.num("fatigue_work_per_hour", 4.0)
		elif n.state == NpcAgent.TRAINING:
			rate = data.num("fatigue_train_per_hour", 7.0)
		elif n.state == NpcAgent.TREATMENT:
			rate = 0.0
		elif n.state == NpcAgent.MOVING and n.running:
			rate = data.num("fatigue_run_per_hour", 12.0)
		cs.fatigue = float(cs.fatigue) + rate * per
	cs.fatigue = clampf(float(cs.fatigue), 0.0, 100.0)


## 활동에 맞는 빈 오브젝트 (없으면 "") — sleep: 회복력 높은 순, rest: 소파·의자·침대(앉기), eat·work: 의자, medical: 의무침대
func _pick_seat(n: NpcAgent, fid: String, activity: String) -> String:
	var kinds: Array = []
	match activity:
		"sleep":
			kinds = ["침대", "의무침대", "소파", "의자"]
		"rest":
			kinds = ["소파", "의자", "침대"]
		"eat", "work":
			kinds = ["의자"]
		"medical":
			kinds = ["의무침대"]
		_:
			return ""
	var cur := ""
	if n.seat != "" and data.objects.get(n.seat, {}).get("facility", "") == fid and data.objects[n.seat].kind in kinds:
		cur = n.seat
	var best := ""
	var best_v := -INF
	for oid in data.objects_in(fid):
		var o: Dictionary = data.objects[oid]
		if not o.kind in kinds or (seat_owner.has(oid) and seat_owner[oid] != n.id):
			continue
		var v: float = float(o.fatigue_rate) + float(o.hp_rate) - kinds.find(o.kind) * 0.01
		if activity != "sleep":
			v = -kinds.find(o.kind) - absf(float(o.x) - 0.5) * 0.1
		if v > best_v:
			best = oid
			best_v = v
	# 지금 자리가 더 나쁜 종류가 아니면 그대로 (같은 방에서 자려면 의자 → 침대로 옮김)
	if cur != "" and (best == "" or kinds.find(data.objects[cur].kind) <= kinds.find(data.objects[best].kind)):
		return cur
	return best


func _claim_seat_here(n: NpcAgent, activity: String) -> void:
	var oid := _pick_seat(n, n.facility, activity)
	if oid != "":
		seat_owner[oid] = n.id
		n.seat = oid
		n.dest_x = data.object_x(oid)
		n.pos = Vector2(n.dest_x, data.floor_line(n.facility))


func _release_seat(n: NpcAgent) -> void:
	if n.seat != "" and seat_owner.get(n.seat, "") == n.id:
		seat_owner.erase(n.seat)
	n.seat = ""


## 화면 자세: {pose: stand|sit|lie, height(m), kind}
func posture(n: NpcAgent) -> Dictionary:
	if n.seat == "" or n.state == NpcAgent.MOVING or n.state == NpcAgent.PLAYER_DIALOGUE:
		return {"pose": "stand", "height": 0.0, "kind": ""}
	var o: Dictionary = data.objects.get(n.seat, {})
	if o.is_empty():
		return {"pose": "stand", "height": 0.0, "kind": ""}
	var asleep := n.activity == "sleep" or n.state == NpcAgent.RECOVERING
	var pose := "sit"
	if asleep and o.kind in ["침대", "의무침대", "소파"]:
		pose = "lie"
	return {"pose": pose, "height": float(o.height), "kind": o.kind}


## 식당에서 식사: 끼니마다 식재료 1 소모, 없으면 굶어서 피로 증가 (피로는 잠으로만 회복)
func _try_meal(n: NpcAgent, m: int) -> void:
	if n.activity != "eat" or n.state != NpcAgent.STAYING or data.facilities.get(n.facility, {}).get("tag", "") != "식당":
		return
	var key := "%d:%d" % [clock.day_index(m), floori(clock.minute_of_day(m) / 180.0)]
	if n.meal_key == key:
		return
	n.meal_key = key
	var cs := cstate(n)
	if food > 0:
		food -= 1
	else:
		cs.fatigue = clampf(float(cs.fatigue) + data.num("hungry_fatigue", 6.0), 0.0, 100.0)
		_log("식재료가 없어 %s 이(가) 끼니를 걸렀습니다 (피로 +%d)" % [n.name, data.inum("hungry_fatigue", 6)])


func mess_facility() -> String:
	for fid in data.facilities_with_tag("식당"):
		if unlocked.has(fid):
			return fid
	return ""


func buy_food() -> Dictionary:
	if mess_facility() == "":
		return _fail("식당이 잠겨 있습니다")
	var price := data.inum("food_pack_price", 20)
	if ledger.cash < price:
		return _fail("달러가 부족합니다 ($%d 더 필요)" % (price - ledger.cash))
	counters.food = int(counters.get("food", 0)) + 1
	var amount := data.inum("food_pack_amount", 12)
	ledger.post("food:%d" % counters.food, _minute, clock.label(_minute), "food", -price, "food", "식재료 %d끼" % amount, week_now())
	food += amount
	_log("식재료 공급 +%d끼 (-$%d) → %d끼" % [amount, price, food])
	return {"ok": true, "msg": "식재료 +%d끼 (남은 %d끼)" % [amount, food]}


# ================================================================ PX · 선물
func px_facility() -> String:
	for fid in data.facilities_with_tag("상점"):
		if unlocked.has(fid):
			return fid
	return ""


func buy_gift(item_id: String) -> Dictionary:
	var it: Dictionary = data.px_items.get(item_id, {})
	if it.is_empty():
		return _fail("없는 물건")
	if px_facility() == "":
		return _fail("PX 가 잠겨 있습니다")
	if ledger.cash < int(it.price):
		return _fail("달러가 부족합니다 ($%d 더 필요)" % (int(it.price) - ledger.cash))
	counters.gift = int(counters.get("gift", 0)) + 1
	ledger.post("px:%d" % counters.gift, _minute, clock.label(_minute), "px", -int(it.price), item_id, "PX %s" % it.name, week_now())
	gifts[item_id] = int(gifts.get(item_id, 0)) + 1
	return {"ok": true, "msg": "%s 구매 (보유 %d)" % [it.name, gifts[item_id]]}


func give_gift(npc_id: String, item_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	var it: Dictionary = data.px_items.get(item_id, {})
	if n == null or it.is_empty():
		return _fail("줄 수 없습니다")
	if int(gifts.get(item_id, 0)) <= 0:
		return _fail("%s 이(가) 없습니다 (PX 에서 구매)" % it.get("name", item_id))
	gifts[item_id] = int(gifts[item_id]) - 1
	var v := data.gift_value(item_id, npc_id)
	var taste := data.gift_taste(item_id, npc_id)
	var liked := taste == "좋아함" or taste == "아주 좋아함"
	_add_affinity(n, float(v))
	var tail: String = {"아주 좋아함": " — 아주 좋아해요!", "좋아함": " — 좋아해요", "별로": " — 별로인 듯"}.get(taste, "")
	_log("%s 에게 %s 선물 — 친밀도 +%d (%s)" % [n.name, it.name, v, taste])
	return {"ok": true, "msg": "%s 친밀도 +%d%s" % [n.name, v, tail], "liked": liked, "taste": taste, "value": v}


# ================================================================ 의무실
func infirmary_facility() -> String:
	for fid in data.facilities_with_tag("의무"):
		if unlocked.has(fid):
			return fid
	return ""


## 우클릭 → 의무실로: 상태 이상이 있으면 치료(시간) 후, 의무침대에서 체력이 다 찰 때까지 휴식
func issue_medical(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	var fid := infirmary_facility()
	if fid == "":
		return _fail("의무실이 잠겨 있습니다")
	var cs := cstate(n)
	if (cs.statuses as Array).is_empty() and float(cs.hp) >= char_max_hp(ckey(n)):
		return _fail("%s 은(는) 치료할 것이 없습니다 (체력 가득, 상태 이상 없음)" % n.name)
	if not n.is_free():
		return _fail("%s 은(는) 지금 다른 일을 하고 있습니다 (%s)" % [n.name, n.state_name()])
	if not reachable(n.facility, fid):
		return _fail("의무실까지 갈 수 있는 길이 없습니다")
	_start_command(n, {"type": "medical", "target": fid, "issuer": "player"})
	var msg := "%s → 의무실 (%s)" % [n.name, "치료 후 휴식" if not (cs.statuses as Array).is_empty() else "체력 회복 휴식"]
	_log(msg)
	return {"ok": true, "msg": msg}


# ================================================================ 전투 발생 · 전투 연계
func _check_battle_rules(m: int) -> void:
	if not pending_battle.is_empty():
		return
	for r in data.battle_rules:
		if BattleRules.fires_at(r, m, clock):
			var stages: Array = r.get("stages", [])
			var st: String = str(stages[rng.randi() % stages.size()]) if not stages.is_empty() else ""
			pending_battle = {"rule": r.id, "name": r.name, "stage": st, "minute": m, "label": clock.label(m), "allow_skip": r.get("allow_skip", false)}
			_log("전투 발생! %s (%s)" % [r.name, st])
			battle_triggered.emit(pending_battle)
			return


## 다음 전투 발생 예정 {minute, rule} (없으면 {})
func next_battle() -> Dictionary:
	return BattleRules.next_of(data.battle_rules, _minute, clock)


## 디버그: 첫 규칙으로 지금 전투 발생 (규칙이 없으면 첫 스테이지)
func debug_trigger_battle() -> void:
	if not pending_battle.is_empty():
		return
	var r: Dictionary = data.battle_rules[0] if not data.battle_rules.is_empty() else {"id": "debug", "name": "디버그 전투", "stages": []}
	var stages: Array = r.get("stages", [])
	pending_battle = {"rule": r.id, "name": r.name, "stage": str(stages[0]) if not stages.is_empty() else "", "minute": _minute,
		"label": clock.label(_minute), "allow_skip": true}
	_log("전투 발생! %s (디버그)" % r.name)
	battle_triggered.emit(pending_battle)


func skip_pending_battle() -> bool:
	if pending_battle.is_empty() or not pending_battle.get("allow_skip", false):
		return false
	_log("전투를 넘김 (%s)" % pending_battle.name)
	pending_battle = {}
	return true


## 전투에 들고 갈 몸 상태 {hp, statuses}
func battle_entry(character_id: String) -> Dictionary:
	var cs := cstate_of(character_id)
	return {"hp": maxi(1, floori(float(cs.hp))), "statuses": (cs.statuses as Array).duplicate()}


## 전투 결과 반영: 잃은 체력 그대로(쓰러지면 1 + 부상), 부정 상태 이상 유지, 참가자 피로 증가
## result.allies = [{id, hp, alive, statuses}]
func apply_battle_result(result: Dictionary) -> void:
	var lines := PackedStringArray()
	growth = []
	for a in result.get("allies", []):
		var cid := str(a.get("id", ""))
		if cid == "":
			continue
		var cs := cstate_of(cid)
		var sts: Array = []
		for sid in a.get("statuses", []):   # 전투 전용 상태 이상(출혈·기절 등)은 전투가 끝나면 사라짐
			var sd := StatusCatalog.get_def(str(sid))
			if not sd.get("positive", false) and not sd.get("battle", false):
				sts.append(str(sid))
		if not a.get("alive", true):
			cs.hp = 1.0
			if not "injured" in sts:
				sts.append("injured")
		else:
			cs.hp = clampf(float(a.get("hp", cs.hp)), 1.0, float(char_max_hp(cid)))
		cs.statuses = sts
		cs.fatigue = clampf(float(cs.fatigue) + data.num("fatigue_battle", 20.0), 0.0, 100.0)
		var gain := data.inum("xp_win", 100) if str(result.get("winner", "")) == "ally" else data.inum("xp_lose", 40)
		var ups := add_xp(cid, gain)
		add_will(cid, data.inum("will_battle", 5))   # 신 캐릭터만
		growth.append({"id": cid, "name": _char_label(cid), "xp": gain, "level": char_level(cid), "ups": ups})
		lines.append("%s HP %d/%d%s" % [_char_label(cid), floori(float(cs.hp)), char_max_hp(cid), " 부상" if "injured" in sts else ""])
	var w := str(result.get("winner", ""))
	battle_history.append({"minute": _minute, "label": clock.label(_minute), "stage": str(result.get("stage", pending_battle.get("stage", ""))),
		"rule": str(pending_battle.get("rule", "")), "winner": w})
	pending_battle = {}
	_log("전투 결과: %s — %s" % ["승리" if w == "ally" else "패배", ", ".join(lines)])
	last_loot = []
	if w == "ally":
		last_loot = _battle_loot(str(battle_history.back().stage))
		trigger_cutscenes("battle_win", str(battle_history.back().stage))
	check_divine()   # 미션(전투 승리) 완료 조건


func _char_label(character_id: String) -> String:
	for id in data.npc_order:
		if data.npcs[id].character_id == character_id:
			return data.npcs[id].name
	return character_id


# ================================================================ 경제 · 결산 · 전리품 · 납품 · 장군 점검
## 보급 데이터 (data/supply.xlsx — 아이템 · 전투 보상 · 대원 선물 · 장군 요구 · 납품 목록 · 주급)
func supply() -> SupplyData:
	if data.supply == null:
		data.supply = SupplyData.new()
	return data.supply


func item_label(id: String) -> String:
	return supply().item_name(id)


func loot_count(id: String) -> int:
	return int(loot.get(id, 0))


func add_loot(id: String, n: int, why: String = "") -> void:
	if n <= 0 or id == "":
		return
	loot[id] = loot_count(id) + n
	if why != "":
		_log("%s: %s ×%d" % [why, item_label(id), n])
	loot_changed.emit()


func _take_loot(id: String, n: int) -> bool:
	if n <= 0 or loot_count(id) < n:
		return false
	loot[id] = loot_count(id) - n
	if int(loot[id]) <= 0:
		loot.erase(id)
	loot_changed.emit()
	return true


## 전투 승리 전리품: 그 스테이지 줄 + "*" 줄을 확률로 굴려 창고에. [{item, name, count}]
func _battle_loot(stage: String) -> Array:
	var got := {}
	var order: Array = []
	for r in supply().battle_loot:
		if str(r.stage) != "*" and str(r.stage) != stage:
			continue
		if rng.randi_range(1, 100) > int(r.chance):
			continue
		var n := rng.randi_range(int(r.min), int(r.max))
		if n <= 0:
			continue
		if not got.has(r.item):
			order.append(r.item)
		got[r.item] = int(got.get(r.item, 0)) + n
	var out := []
	for it in order:
		add_loot(it, got[it])
		out.append({"item": it, "name": item_label(it), "count": got[it]})
	if not out.is_empty():
		_log("전리품: " + ", ".join(out.map(func(e): return "%s ×%d" % [e.name, e.count])))
	return out


## 대원 선물: 그 대원과 하루 첫 대화 때 확률로 (최소 친밀도 이상). 준 것 {item, name, count} 또는 {}
func _crew_gift(n: NpcAgent) -> Dictionary:
	for r in supply().crew_gifts:
		if str(r.npc) != n.id or float(cstate(n).get("affinity", 0.0)) < float(r.affinity):
			continue
		if rng.randi_range(1, 100) <= int(r.chance):
			add_loot(str(r.item), 1, "%s 이(가) 건넴" % n.name)
			return {"item": str(r.item), "name": item_label(str(r.item)), "count": 1}
	return {}


## 스토리 진행률 % = 완료한 퀘스트 / 전체 퀘스트 (퀘스트가 없으면 0) — 주마다 납품 목록을 고르는 기준
func story_progress() -> float:
	var defs := quest_defs()
	if defs.is_empty():
		return 0.0
	var done := 0
	for q in defs:
		if quest_status(str(q.id)) == "done":
			done += 1
	return 100.0 * done / defs.size()


## 그 주 납품 {req: {아이템: 개수}, done: {아이템: 개수}} — 처음 볼 때 그때의 스토리 진행률로 목록을 정해 둠 (주 중간에 바뀌지 않게)
func delivery(week: int = -1) -> Dictionary:
	if week < 0:
		week = week_now()
	var k := str(week)
	if not deliveries.has(k):
		deliveries[k] = {"req": supply().delivery_for(story_progress(), week), "done": {}}
	return deliveries[k]


## 납품 비율 0~1 (목록 개수 합 중 낸 개수, 목록이 없으면 1)
func delivery_rate(week: int = -1) -> float:
	var d := delivery(week)
	var need := 0
	var got := 0
	for it in d.req:
		need += int(d.req[it])
		got += mini(int(d.done.get(it, 0)), int(d.req[it]))
	return 1.0 if need == 0 else float(got) / need


## 그 주 주급 = 기본 주급 × 납품 비율
func expected_pay(week: int = -1) -> int:
	return roundi(supply().inum("base_pay", 150) * delivery_rate(week))


## 이번 주 납품: 창고에서 그 아이템을 n개(남은 만큼까지) 냄. {ok, msg}
func deliver(item: String, n: int = 1) -> Dictionary:
	var d := delivery()
	var left := int(d.req.get(item, 0)) - int(d.done.get(item, 0))
	if left <= 0:
		return _fail("%s 은(는) 이번 주 납품 목록에 없거나 다 냈습니다" % item_label(item))
	var k := mini(n, mini(left, loot_count(item)))
	if k <= 0:
		return _fail("창고에 %s 이(가) 없습니다" % item_label(item))
	_take_loot(item, k)
	d.done[item] = int(d.done.get(item, 0)) + k
	var msg := "납품: %s ×%d — 이번 주 %d%% (주급 $%d 예정)" % [item_label(item), k, roundi(delivery_rate() * 100.0), expected_pay()]
	_log(msg)
	return {"ok": true, "msg": msg}


func _settle(week: int) -> void:
	_close_demand(week)   # 결산까지 대답 안 한 장군 요구 = 거절
	var rate := delivery_rate(week)
	var pay := roundi(supply().inum("base_pay", 150) * rate)
	var st := ledger.settle(week, pay, _minute, clock.label(_minute), "주급 (납품 %d%%)" % roundi(rate * 100.0), "pay")
	if st.is_empty():
		return
	st.delivery = delivery(week).duplicate(true)
	st.rate = rate
	_log("%d주차 결산: %s$%d (주급 $%d · 납품 %d%%, 잔액 $%d)" % [week + 1, "+" if int(st.total) >= 0 else "-", absi(int(st.total)), pay, roundi(rate * 100.0), st.cash])
	statement_ready.emit(st)


func _schedule_inspection(from_minute: int) -> void:
	var key := clock.month_key(from_minute)
	if inspections.has(key):
		return
	var b := clock.month_bounds(from_minute)
	inspections[key] = {"month": key, "minute": rng.randi_range(from_minute, b.y - 1), "done": false}


func inspection_this_month() -> Dictionary:
	return inspections.get(clock.month_key(_minute), {})


## 장군 점검: 그 달 정한 시각이 되면 장군이 와서 아이템을 요구 (supply.xlsx 장군 요구 — 지난번과 다른 것). 결산 전까지 준다/안 준다
func _check_inspection(m: int) -> void:
	var ins: Dictionary = inspections.get(clock.month_key(m), {})
	if ins.is_empty() or ins.done or m < int(ins.minute):
		return
	var dm := _pick_demand(str(ins.month))
	ins.done = true
	ins.item = str(dm.get("item", ""))
	ins.count = int(dm.get("count", 0))
	ins.line = str(dm.get("line", ""))
	ins.answer = "" if ins.item != "" else "none"
	ins.week = week_now()
	ins.date = clock.label(m)
	if ins.item != "":
		_log("장군 점검: %s ×%d 을(를) 요구 — 이번 주 결산 전까지 대답 (창고 %d개)" % [item_label(ins.item), ins.count, loot_count(ins.item)])
	else:
		_log("장군 점검: 요구 없음")
	inspection_completed.emit(ins)


## 요구 아이템: 가중치로 고르되 지난 점검과 다른 것 (후보가 하나뿐이면 같아도)
func _pick_demand(month: String) -> Dictionary:
	var prev := ""
	var keys := inspections.keys()
	keys.sort()
	for k in keys:
		if str(k) < month and str(inspections[k].get("item", "")) != "":
			prev = str(inspections[k].item)
	var pool := supply().demands.filter(func(d): return int(d.weight) > 0 and str(d.item) != "")
	if pool.size() > 1:
		pool = pool.filter(func(d): return str(d.item) != prev)
	if pool.is_empty():
		return {}
	var total := 0
	for d in pool:
		total += int(d.weight)
	var roll := rng.randi_range(1, total)
	for d in pool:
		roll -= int(d.weight)
		if roll <= 0:
			return d
	return pool.back()


## 대답을 기다리는 장군 요구 (없으면 {})
func pending_demand() -> Dictionary:
	for k in inspections:
		var r: Dictionary = inspections[k]
		if bool(r.done) and str(r.get("item", "")) != "" and str(r.get("answer", "")) == "":
			return r
	return {}


## 장군 요구에 대답: give = 창고에서 그 아이템을 줌 → 그 주 결산 추가금 · 충성심 +, 안 줌 → 결산 차감 · 충성심 −. {ok, msg}
func answer_demand(give: bool, why: String = "") -> Dictionary:
	var r := pending_demand()
	if r.is_empty():
		return _fail("대답할 장군 요구가 없습니다")
	var sp := supply()
	var msg := ""
	if give:
		if not _take_loot(str(r.item), int(r.count)):
			return _fail("창고에 %s 이(가) %d개 있어야 합니다 (지금 %d개)" % [item_label(str(r.item)), int(r.count), loot_count(str(r.item))])
		r.answer = "give"
		var bonus := sp.inum("general_bonus", 40)
		ledger.add_pending("general:" + str(r.month), "general", bonus, str(r.month), "장군 요구에 응함 (%s ×%d)" % [item_label(str(r.item)), int(r.count)], int(r.week))
		_add_loyalty(sp.inum("loyalty_give", 5))
		msg = "장군에게 %s ×%d 을(를) 줬습니다 — 결산 때 +$%d, 충성심 %d" % [item_label(str(r.item)), int(r.count), bonus, loyalty]
	else:
		r.answer = "refuse"
		var pen := sp.inum("general_penalty", 40)
		ledger.add_pending("general:" + str(r.month), "general", -pen, str(r.month), "장군 요구 거절 (%s ×%d)%s" % [item_label(str(r.item)), int(r.count), why], int(r.week))
		_add_loyalty(sp.inum("loyalty_refuse", -10))
		msg = "장군의 요구를 거절했습니다%s — 결산 때 -$%d, 충성심 %d" % [why, pen, loyalty]
	_log(msg)
	return {"ok": true, "msg": msg}


## 결산: 그 주(또는 그 전)의 요구에 대답이 없으면 거절로 처리
func _close_demand(week: int) -> void:
	var r := pending_demand()
	if not r.is_empty() and int(r.week) <= week:
		answer_demand(false, " — 결산까지 대답 없음")


func _add_loyalty(v: int) -> void:
	loyalty = clampi(loyalty + v, 0, 100)


## 디버그: 이번 달 점검을 지금 실행 (이미 했으면 아무것도 안 함)
func debug_inspect_now() -> void:
	var ins := inspection_this_month()
	if ins.is_empty() or ins.done:
		return
	ins.minute = _minute
	_check_inspection(_minute)


# ================================================================ 기록
func _log(text: String) -> void:
	log_lines.append("%s  %s" % [clock.label(_minute), text])
	if log_lines.size() > 300:
		log_lines = log_lines.slice(log_lines.size() - 300)
	notice.emit(text)


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "msg": msg}


# ================================================================ 저장 · 불러오기
func to_dict() -> Dictionary:
	var nd := {}
	for id in npcs:
		nd[id] = npcs[id].to_dict()
	return {"version": SAVE_VERSION, "total_minutes": clock.total_minutes, "minute": _minute, "day": _day, "month": _month,
		"rng_seed": str(rng.seed), "rng_state": str(rng.state), "ledger": ledger.to_dict(), "unlocked": unlocked.keys(),
		"loot": loot, "water": water, "deliveries": deliveries, "loyalty": loyalty, "npcs": nd, "chats": chats, "jobs": jobs, "claimed_contracts": claimed_contracts.keys(),
		"opened_contracts": opened_contracts.keys(), "request_state": request_state, "conv_counts": conv_counts, "heard": heard,
		"story_seen": story_seen, "inspections": inspections, "progression": progression, "inventory": inventory,
		"workshop": workshop, "researched": researched.keys(), "research": research, "counters": counters, "log": log_lines.slice(maxi(0, log_lines.size() - 100)),
		"chars": chars, "food": food, "gifts": gifts, "pending_battle": pending_battle, "battle_history": battle_history, "divine_unlocked": divine_unlocked.keys(),
		"quests": quests, "talk_counts": talk_counts,
		"cutscene_queue": cutscene_queue, "cutscenes_seen": cutscenes_seen}


static func from_dict(p_data: OutgameData, p_battle: GameData, d: Dictionary) -> BaseSim:
	var s := BaseSim.new()
	s.data = p_data
	s.battle = p_battle
	s.clock.setup(p_data.text("start_date", "2048-04-07"), 0)
	s.clock.total_minutes = float(d.get("total_minutes", 480.0))
	s._minute = int(d.get("minute", s.clock.minute_int()))
	s._day = int(d.get("day", s.clock.day_index(s._minute)))
	s._month = str(d.get("month", s.clock.month_key(s._minute)))
	s.rng.seed = int(str(d.get("rng_seed", "2048")))
	s.rng.state = int(str(d.get("rng_state", "0")))
	s.ledger.from_dict(d.get("ledger", {}))
	for f in d.get("unlocked", []):
		s.unlocked[str(f)] = true
	var lt: Dictionary = d.get("loot", {})
	for k in lt:
		s.loot[str(k)] = int(lt[k])
	var dv: Dictionary = d.get("deliveries", {})
	for k in dv:
		var e0: Dictionary = dv[k]
		var req := {}
		var done := {}
		for it in e0.get("req", {}):
			req[str(it)] = int(e0.req[it])
		for it in e0.get("done", {}):
			done[str(it)] = int(e0.done[it])
		s.deliveries[str(k)] = {"req": req, "done": done}
	s.loyalty = int(d.get("loyalty", s.supply().inum("loyalty_start", 50)))
	s.water = int(d.get("water", s.supply().inum("water_start", 12)))
	s.jobs = d.get("jobs", [])
	for c in d.get("claimed_contracts", []):
		s.claimed_contracts[str(c)] = true
	for c in d.get("opened_contracts", []):
		s.opened_contracts[str(c)] = true
	s.request_state = d.get("request_state", {})
	s.conv_counts = d.get("conv_counts", {})
	s.heard = d.get("heard", {})
	s.story_seen = d.get("story_seen", {})
	s.inspections = d.get("inspections", {})
	for k in s.inspections:
		s.inspections[k].minute = int(s.inspections[k].minute)
		for f in ["count", "week"]:
			if s.inspections[k].has(f):
				s.inspections[k][f] = int(s.inspections[k][f])
	s.progression = d.get("progression", {})
	for c in d.get("divine_unlocked", []):
		s.divine_unlocked[str(c)] = true
	var qd: Dictionary = d.get("quests", {})
	for k in qd:
		var e: Dictionary = qd[k]
		s.quests[str(k)] = {"state": str(e.get("state", "active")), "step": int(e.get("step", 0)), "base": int(e.get("base", 0)),
			"started": int(e.get("started", 1)), "finished": int(e.get("finished", -1))}
	s.cutscene_queue = (d.get("cutscene_queue", []) as Array).map(func(x): return str(x))
	var cs0: Dictionary = d.get("cutscenes_seen", {})
	for k in cs0:
		s.cutscenes_seen[str(k)] = int(cs0[k])
	var tc: Dictionary = d.get("talk_counts", {})
	for k in tc:
		s.talk_counts[str(k)] = int(tc[k])
	s.inventory = d.get("inventory", [])
	for it in s.inventory:
		it.plus = int(it.plus)
		it.slot = int(it.slot)
	s.workshop = d.get("workshop", {})
	for q in d.get("researched", []):
		s.researched[str(q)] = true
	s.research = d.get("research", {})
	if not s.research.is_empty():
		s.research.remaining = int(s.research.remaining)
		s.research.total = int(s.research.total)
	var cn: Dictionary = d.get("counters", {})
	for k in cn:
		s.counters[k] = int(cn.get(k, 0))
	s.chars = d.get("chars", {})
	for k in s.chars:
		var c: Dictionary = s.chars[k]
		c.hp = float(c.get("hp", 0))
		c.fatigue = float(c.get("fatigue", 0))
		c.affinity = float(c.get("affinity", 0))
		c.talk_day = int(c.get("talk_day", -1))
		c.statuses = (c.get("statuses", []) as Array).map(func(x): return str(x))
	s.food = int(d.get("food", p_data.inum("food_start", 10)))
	s.gifts = d.get("gifts", {})
	for k in s.gifts:
		s.gifts[k] = int(s.gifts[k])
	s.pending_battle = d.get("pending_battle", {})
	s.battle_history = d.get("battle_history", [])
	s.log_lines = d.get("log", [])
	s._add_missing_npcs()
	var nd: Dictionary = d.get("npcs", {})
	for id in nd:
		if s.npcs.has(id):
			s.npcs[id].from_dict(nd[id])
	# 시설 배치가 바뀐 저장(없는 시설·오브젝트)은 시작 장소로 되돌림
	for n in s.npcs.values():
		if not p_data.facilities.has(n.facility):
			n.facility = str(p_data.npcs[n.id].start)
			n.pos = Vector2(s._slot_x(n, n.facility), p_data.floor_line(n.facility))
			n.state = NpcAgent.STAYING
			n.command = {}
		if not p_data.facilities.has(n.dest):
			n.dest = n.facility
		if n.seat != "" and (not p_data.objects.has(n.seat) or s.seat_owner.has(n.seat)):
			n.seat = ""
		if n.seat != "":
			s.seat_owner[n.seat] = n.id
	# 진행 중이던 대원끼리 대화
	for ch in d.get("chats", []):
		ch.end = int(ch.end)
		s.chats.append(ch)
		for id in [ch.a, ch.b]:
			if s.npcs.has(id):
				s.npcs[id].chat_key = ch.key
	s._rebuild_changes()
	# 이동 중이던 대원은 목적지까지 경로를 다시 계산
	for n in s.npcs.values():
		if n.state == NpcAgent.PLAYER_DIALOGUE:
			n.state = n.resume_state if n.resume_state != "" else NpcAgent.STAYING
		if n.state == NpcAgent.MOVING:
			var target: String = str(n.command.target) if not n.command.is_empty() else n.dest
			n.dest = ""
			if not s._go(n, target):
				n.state = NpcAgent.STAYING
	s.check_divine()   # 불러온 뒤 이미 조건을 채운 캐릭터
	return s
