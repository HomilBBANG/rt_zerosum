class_name BaseSim
extends RefCounted
## 아웃게임 기지 시뮬레이션 (화면과 분리 — 헤드리스 테스트 가능).
## 시계 · 시설 해금 · 대원 주간 일정 이동 · 대화/엿듣기/요청 · 일일 오염/청소/위임 · 업무/외부 의뢰 ·
## 주간 결산 · 월 1회 장군 점검 · 훈련/제작/강화 · 저장/불러오기.
## 처리 순서 (매 게임 분): 날짜 전환(결산 → 월 전환 → 일일 오염) → 정각 → 점검 → 작업실 → 대원 → 대화.
## 날짜가 바뀌는 판단은 시계만 하고, UI 는 이 클래스의 함수만 호출한다 (03_IMPLEMENTATION_HANDOFF 4절).

signal hour_changed(minute: int)
signal day_changed(day: int)
signal month_changed(key: String)
signal room_unlocked(fid: String)
signal npc_state_changed(npc_id: String)
signal cleanliness_changed(fid: String)
signal job_completed(job: Dictionary)
signal inspection_completed(record: Dictionary)
signal statement_ready(statement: Dictionary)
signal notice(text: String)

const SAVE_VERSION := 1

var data: OutgameData
var battle: GameData                 # 전투 캐릭터·아이템 (초기 장비·무기 이름). 없으면 무기고 비어 있음
var clock := WorldClock.new()
var rng := RandomNumberGenerator.new()
var ledger := EconomyLedger.new()
var unlocked: Dictionary = {}        # fid → true
var cleanliness: Dictionary = {}     # fid → 0~100
var dirt: Array = []                 # [{id, facility, x(방 폭 비율), kind}]
var npcs: Dictionary = {}            # npc id → NpcAgent
var chats: Array = []                # [{key, conv, a, b, facility, end, story}]
var jobs: Array = []                 # [{uid, contract, npc, state, minute}]
var claimed_contracts: Dictionary = {}
var opened_contracts: Dictionary = {}
var request_state: Dictionary = {}   # 요청 id → "accepted"
var conv_counts: Dictionary = {}     # 대화이벤트 id → 발생 횟수
var heard: Dictionary = {}           # 대화이벤트 id → 엿들은 횟수
var story_seen: Dictionary = {}      # 스토리 이벤트 id → 처음 엿들은 시각 라벨
var inspections: Dictionary = {}     # "YYYY-MM" → {month, minute, done, score, grade, bonus, week, date}
var progression: Dictionary = {}     # 전투 캐릭터 id → {training}
var inventory: Array = []            # [{uid, item, plus, owner(캐릭터 id 또는 ""), slot}]
var workshop: Dictionary = {}        # {kind: craft|enhance, recipe?, uid?, remaining, total}
var counters: Dictionary = {"dirt": 0, "job": 0, "inv": 0, "chat": 0}
var log_lines: Array = []
var cleaning_log: Array = []         # [{minute, requested, executing, facility, result}]
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
		cleanliness[fid] = data.num("initial_cleanliness", 90.0)
	_add_missing_npcs()
	_init_inventory()
	_minute = clock.minute_int()
	_day = clock.day_index(_minute)
	_month = clock.month_key(_minute)
	_schedule_inspection(_minute)
	_rebuild_changes()
	_log("기지 운영 시작")
	for id in data.npc_order:
		_npc_minute(npcs[id], _minute)


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
		if not cleanliness.has(fid):
			cleanliness[fid] = data.num("initial_cleanliness", 90.0)
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
	_tick_workshop()
	for id in data.npc_order:
		if npcs.has(id):
			_npc_minute(npcs[id], m)
	_tick_chats(m)
	_try_conversations(m)


func _new_day(d: int) -> void:
	day_changed.emit(d)
	if d % week_days() == 0:
		_settle(floori(d / float(week_days())) - 1)
	var key := clock.month_key(d * 1440)
	if key != _month:
		_month = key
		month_changed.emit(key)
		_schedule_inspection(d * 1440)
	_daily_dirt()
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
	cleanliness[fid] = data.num("initial_cleanliness", 90.0)
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
	if not n.command.is_empty():
		return   # 지시 장소로 이동 중
	var mod := clock.minute_of_day(m)
	var changes: Dictionary = _changes.get(n.id, {}).get(clock.weekday(m), {})
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
	if want.facility != n.dest:
		_go(n, want.facility)
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


func _go(n: NpcAgent, fid: String) -> bool:
	var route := RoomRouteService.find_path(data, n.facility, fid, _is_open)
	if route.is_empty():
		n.dest_reason = "%s 로 가는 길 없음" % data.facility_name(fid)
		return false
	n.dest = fid
	n.dest_x = _slot_x(n, fid)
	n.path = RoomRouteService.waypoints(data, route, n.dest_x)
	n.state = NpcAgent.MOVING
	npc_state_changed.emit(n.id)
	return true


func _move(step: float) -> void:
	var speed := data.num("walk_speed", 90.0)
	for n in npcs.values():
		if n.state != NpcAgent.MOVING:
			continue
		var dist := speed * step
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
	var c := n.command
	if c.is_empty():
		n.state = NpcAgent.STAYING
	else:
		match str(c.type):
			"clean":
				n.state = NpcAgent.CLEANING
				n.busy = data.num("clean_minutes", 20.0)
			"train":
				n.state = NpcAgent.TRAINING
				n.busy = data.num("train_minutes", 120.0)
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
	var req := active_request(npc_id)
	var dlg: String = req.dialogue if not req.is_empty() else str(data.npcs.get(npc_id, {}).get("talk", ""))
	return {"lines": data.dialogues.get(dlg, []), "request": req}


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
	var eff: String = q.effect
	var msg := "요청 수락"
	if eff.begins_with("의뢰:"):
		var cid := eff.substr(3).strip_edges()
		opened_contracts[cid] = true
		msg = "요청 수락 — 의뢰 '%s' 이(가) 열렸습니다" % data.jobs.get(cid, {}).get("name", cid)
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
		"title": "%s · %s 의 대화" % [data.npc_name(ch.a), data.npc_name(ch.b)]}


# ================================================================ 위생 · 청소
func cleanable(fid: String) -> bool:
	return data.facilities.get(fid, {}).get("cleanable", false)


func hygiene_score() -> float:
	var total := 0.0
	var n := 0
	for fid in data.facility_order:
		if unlocked.has(fid) and cleanable(fid):
			total += float(cleanliness.get(fid, 100.0))
			n += 1
	return total / n if n > 0 else 100.0


func dirt_in(fid: String) -> Array:
	return dirt.filter(func(d): return d.facility == fid)


func add_dirt(fid: String) -> void:
	counters.dirt += 1
	dirt.append({"id": "dirt_%d" % counters.dirt, "facility": fid, "x": rng.randf_range(0.14, 0.86), "kind": rng.randi_range(0, 2)})
	cleanliness[fid] = maxf(0.0, float(cleanliness.get(fid, 100.0)) - data.num("dirt_amount", 20.0))
	_log("%s 이(가) 더러워졌습니다 (청결 %d)" % [data.facility_name(fid), int(cleanliness[fid])])
	cleanliness_changed.emit(fid)


func _daily_dirt() -> void:
	var cands: Array[String] = []
	for fid in data.facility_order:
		if unlocked.has(fid) and cleanable(fid):
			cands.append(fid)
	if cands.is_empty():
		return
	var count := rng.randi_range(data.inum("dirt_min", 1), maxi(data.inum("dirt_min", 1), data.inum("dirt_max", 2)))
	for i in count:
		add_dirt(cands[rng.randi() % cands.size()])


func cleaner_of(fid: String) -> String:
	for n in npcs.values():
		if str(n.command.get("type", "")) == "clean" and n.command.get("target", "") == fid:
			return n.id
	return ""


## 우클릭 → 청소 → 장소. {ok, msg, executor}. 위임 성향이 있으면 다른 대원이 대신 함
func issue_clean(npc_id: String, fid: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
	if not n.is_free():
		return _fail("%s 은(는) 지금 다른 일을 하고 있습니다 (%s)" % [n.name, n.state_name()])
	if not data.facilities.has(fid):
		return _fail("청소할 장소를 클릭하세요")
	if not unlocked.has(fid):
		return _fail("잠긴 방은 청소할 수 없습니다")
	if not cleanable(fid):
		return _fail("%s 은(는) 청소 대상이 아닙니다" % data.facility_name(fid))
	if float(cleanliness.get(fid, 100.0)) >= 100.0 and dirt_in(fid).is_empty():
		return _fail("%s 은(는) 이미 깨끗합니다" % data.facility_name(fid))
	var other := cleaner_of(fid)
	if other != "":
		return _fail("%s 이(가) 이미 청소하러 가는 중입니다" % data.npc_name(other))
	var exec := n
	var msg := ""
	var rules: Dictionary = data.schedules.get(npc_id, {}).get("delegation_rules", {})
	if rules.get("can_delegate_cleaning", false) and rng.randf() < float(rules.get("chance", 1.0)):
		var cand := _delegate_candidate(n, fid, rules)
		if cand != null:
			exec = cand
			msg = "%s 이(가) 청소를 %s 에게 넘겼습니다" % [n.name, cand.name]
		elif not rules.get("self_if_none", true):
			cleaning_log.append({"minute": _minute, "requested": npc_id, "executing": "", "facility": fid, "result": "위임 실패"})
			return _fail("%s 이(가) 청소를 맡길 사람이 없다며 거절했습니다" % n.name)
	if not reachable(exec.facility, fid):
		return _fail("%s 에서 %s 까지 갈 수 있는 길이 없습니다 (잠긴 방)" % [data.facility_name(exec.facility), data.facility_name(fid)])
	_start_command(exec, {"type": "clean", "target": fid, "issuer": npc_id})
	cleaning_log.append({"minute": _minute, "requested": npc_id, "executing": exec.id, "facility": fid, "result": "지시"})
	if msg == "":
		msg = "%s 이(가) %s 청소하러 갑니다" % [exec.name, data.facility_name(fid)]
	_log(msg)
	return {"ok": true, "msg": msg, "executor": exec.id}


func _delegate_candidate(n: NpcAgent, fid: String, rules: Dictionary) -> NpcAgent:
	var best: NpcAgent = null
	var best_d := INF
	var ids: Array = rules.get("delegate_to", [])
	if ids.is_empty():
		ids = data.npc_order
	for id in ids:
		var c: NpcAgent = npcs.get(str(id))
		if c == null or c == n or not c.is_free() or c.state == NpcAgent.CHATTING:
			continue
		if not reachable(c.facility, fid):
			continue
		var d := c.pos.distance_to(n.pos)
		if d < best_d:
			best = c
			best_d = d
	return best


func _complete_clean(fid: String, by: NpcAgent) -> void:
	dirt = dirt.filter(func(d): return d.facility != fid)
	cleanliness[fid] = 100.0
	cleaning_log.append({"minute": _minute, "requested": by.command.get("issuer", by.id), "executing": by.id, "facility": fid, "result": "완료"})
	_log("%s 이(가) %s 청소를 마쳤습니다" % [by.name, data.facility_name(fid)])
	cleanliness_changed.emit(fid)


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


func training_facility() -> String:
	for fid in data.facilities_with_tag("훈련"):
		if unlocked.has(fid):
			return fid
	return ""


func issue_train(npc_id: String) -> Dictionary:
	var n: NpcAgent = npcs.get(npc_id)
	if n == null:
		return _fail("없는 대원")
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


func _start_command(n: NpcAgent, cmd: Dictionary) -> void:
	if n.state == NpcAgent.CHATTING:
		_end_chat_of(n, _minute)
	n.command = cmd
	if not _go(n, str(cmd.target)):
		n.command = {}
		return
	npc_state_changed.emit(n.id)


func _finish_command(n: NpcAgent) -> void:
	var c := n.command
	match str(c.get("type", "")):
		"clean":
			_complete_clean(str(c.target), n)
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
	n.need_think = true   # 지시 완료 → 현재 요일·시각 일정으로 복귀
	npc_state_changed.emit(n.id)


# ================================================================ 작업실: 제작 · 강화
func workshop_facility() -> String:
	for fid in data.facilities_with_tag("작업"):
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
		return _fail("작업실이 잠겨 있습니다")
	if not workshop.is_empty():
		return _fail("작업실이 다른 작업 중입니다")
	var r: Dictionary = data.recipes.get(rid, {})
	if r.is_empty():
		return _fail("없는 레시피")
	workshop = {"kind": "craft", "recipe": rid, "remaining": int(r.minutes), "total": int(r.minutes)}
	_log("제작 시작: %s (%d분)" % [r.name, r.minutes])
	return {"ok": true, "msg": "제작 시작: %s" % r.name}


func start_enhance(uid: String) -> Dictionary:
	if workshop_facility() == "":
		return _fail("작업실이 잠겨 있습니다")
	if not workshop.is_empty():
		return _fail("작업실이 다른 작업 중입니다")
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


# ================================================================ 경제 · 결산 · 점검
func _settle(week: int) -> void:
	var st := ledger.settle(week, data.inum("weekly_subsidy", 100), _minute, clock.label(_minute))
	if st.is_empty():
		return
	_log("%d주차 결산: +$%d (잔액 $%d)" % [week + 1, st.total, st.cash])
	statement_ready.emit(st)


func _schedule_inspection(from_minute: int) -> void:
	var key := clock.month_key(from_minute)
	if inspections.has(key):
		return
	var b := clock.month_bounds(from_minute)
	inspections[key] = {"month": key, "minute": rng.randi_range(from_minute, b.y - 1), "done": false}


func inspection_this_month() -> Dictionary:
	return inspections.get(clock.month_key(_minute), {})


func _check_inspection(m: int) -> void:
	var ins: Dictionary = inspections.get(clock.month_key(m), {})
	if ins.is_empty() or ins.done or m < int(ins.minute):
		return
	var score := hygiene_score()
	var grade := "불만"
	var bonus := data.inum("inspect_bad_bonus", 0)
	if score >= data.num("inspect_good_score", 80.0):
		grade = "만족"
		bonus = data.inum("inspect_good_bonus", 60)
	elif score >= data.num("inspect_ok_score", 50.0):
		grade = "보통"
		bonus = data.inum("inspect_ok_bonus", 30)
	ins.done = true
	ins.score = snappedf(score, 0.1)
	ins.grade = grade
	ins.bonus = bonus
	ins.week = week_now()
	ins.date = clock.label(m)
	ledger.add_pending("inspection:" + str(ins.month), "inspection", bonus, str(ins.month), "장군 점검 보너스 (%s, %s)" % [ins.month, grade], ins.week)
	_log("장군 점검: 환경 미화 %d점 → %s, 이번 주 결산 보너스 $%d" % [roundi(score), grade, bonus])
	inspection_completed.emit(ins)


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
		"cleanliness": cleanliness, "dirt": dirt, "npcs": nd, "chats": chats, "jobs": jobs, "claimed_contracts": claimed_contracts.keys(),
		"opened_contracts": opened_contracts.keys(), "request_state": request_state, "conv_counts": conv_counts, "heard": heard,
		"story_seen": story_seen, "inspections": inspections, "progression": progression, "inventory": inventory,
		"workshop": workshop, "counters": counters, "log": log_lines.slice(maxi(0, log_lines.size() - 100)), "cleaning_log": cleaning_log}


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
	for k in d.get("cleanliness", {}):
		s.cleanliness[k] = float(d.cleanliness[k])
	for fid in p_data.facility_order:
		if not s.cleanliness.has(fid):
			s.cleanliness[fid] = p_data.num("initial_cleanliness", 90.0)
	s.dirt = d.get("dirt", [])
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
	s.progression = d.get("progression", {})
	s.inventory = d.get("inventory", [])
	for it in s.inventory:
		it.plus = int(it.plus)
		it.slot = int(it.slot)
	s.workshop = d.get("workshop", {})
	var cn: Dictionary = d.get("counters", {})
	for k in s.counters:
		s.counters[k] = int(cn.get(k, 0))
	s.log_lines = d.get("log", [])
	s.cleaning_log = d.get("cleaning_log", [])
	s._add_missing_npcs()
	var nd: Dictionary = d.get("npcs", {})
	for id in nd:
		if s.npcs.has(id):
			s.npcs[id].from_dict(nd[id])
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
	return s
