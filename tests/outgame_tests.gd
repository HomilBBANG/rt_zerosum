extends RefCounted
## 아웃게임 기지 검증 (01_OUTGAME_GDD 12절 수용 기준 · 03_HANDOFF 10절 검증 자동화). run_tests.gd 에서 호출.

var check: Callable
var data: OutgameData
var battle: GameData


func _c(cond: bool, name: String) -> void:
	check.call(cond, name)


func run(p_check: Callable) -> void:
	check = p_check
	data = OutgameData.load_from()
	battle = GameData.load_from()
	_c(data != null, "data/outgame.xlsx 읽기")
	if data == null:
		return
	_c(data.warnings.is_empty(), "아웃게임 데이터 참조 오류 없음 %s" % [data.warnings])
	_test_clock()
	_test_unlock()
	_test_routes()
	_test_schedules()
	_test_dialogue()
	_test_cleaning()
	_test_settlement()
	_test_inspection()
	_test_progression()
	_test_save_load()
	_test_stairs_walk()
	_test_fatigue_objects()
	_test_hp_medical()
	_test_food_px_affinity()
	_test_battle_rules()


func _sim() -> BaseSim:
	return BaseSim.create(data, battle)


func _test_clock() -> void:
	print("[15] 시계: 2048-04-07 시작, 24시간마다 하루, 월말·연말")
	var s := _sim()
	_c(s.clock.label() == "2048-04-07 (화) 08:00", "시작 = 2048-04-07 (화) 08:00 (%s)" % s.clock.label())
	var days := []
	s.day_changed.connect(func(d): days.append(d))
	s.skip(23 * 60 + 59 - 8 * 60)
	_c(s.clock.label() == "2048-04-07 (화) 23:59", "23:59 까지 날짜 그대로")
	s.skip(1)
	_c(s.clock.label() == "2048-04-08 (수) 00:00" and days == [1], "23:59 → 2048-04-08 00:00, day_changed 1회")
	s.skip(1440 * 3)
	_c(days == [1, 2, 3, 4], "3일 더 → 날짜 이벤트 정확히 하루 1번")
	var c := WorldClock.new()
	c.setup("2048-04-07", 0)
	c.total_minutes = (c.day_of("2048-04-30") * 1440 + 1439)
	var a := c.date_str()
	c.total_minutes += 1
	_c(a == "2048-04-30" and c.date_str() == "2048-05-01" and c.month_key() == "2048-05", "월말 4/30 → 5/1")
	c.total_minutes = (c.day_of("2048-12-31") * 1440 + 1439)
	c.total_minutes += 1
	_c(c.date_str() == "2049-01-01", "연말 12/31 → 2049-01-01")
	var mb := c.month_bounds()
	_c(mb.y - mb.x == 31 * 1440, "1월 = 31일")


func _test_unlock() -> void:
	print("[16] 달러 해금: 부족 / 정확 / 초과 / 중복 클릭 (자유 건설 없음)")
	var s := _sim()
	_c(s.ledger.cash == 150, "시작 달러 $150")
	_c(s.is_unlocked("f1_lounge") and s.is_unlocked("b1_quarters") and not s.is_unlocked("f1_mess"), "지상 1층·지하 1층 기본 개방, 잠금 방 있음")
	_c(not s.is_unlocked("b2_storage") and not s.is_unlocked("b2_stair_w"), "세 번째 층(지하 2층) 잠금")
	var r := s.try_unlock("f1_mess")
	_c(r.ok and s.ledger.cash == 100, "식당 해금 $50 → 잔액 $100 (초과 보유)")
	r = s.try_unlock("f1_mess")
	_c(not r.ok and s.ledger.cash == 100, "같은 방 다시 클릭 → '이미 해금', 돈 그대로")
	s.ledger.cash = 90
	r = s.try_unlock("b1_training")
	_c(r.ok and s.ledger.cash == 0, "훈련실 $90 = 잔액 정확히 $90 → 해금, 잔액 0")
	r = s.try_unlock("b2_stair_w")
	_c(not r.ok and str(r.msg).contains("$40") and s.ledger.cash == 0, "부족 → 실패, 부족 금액 안내 (%s)" % r.msg)
	_c(not s.try_unlock("room_new_anywhere").ok, "없는 위치는 해금/신축 불가")
	var n := 0
	for e in s.ledger.entries:
		if e.id == "unlock:f1_mess":
			n += 1
	_c(n == 1, "원장에 해금 항목 1번만")


func _test_routes() -> void:
	print("[17] 시설 연결 그래프: 잠긴 방은 지나가지 못함, 해금 후 경로 갱신")
	var s := _sim()
	var open := func(f): return s.is_unlocked(f)
	var p := RoomRouteService.find_path(data, "f1_lounge", "b1_workshop", open)
	_c(p == ["f1_lounge", "f1_office", "f1_stair_w", "b1_stair_w", "b1_quarters", "b1_infirmary", "b1_workshop"], "공용실 → 무기고: 서쪽 계단으로 (%s)" % [p])
	_c(RoomRouteService.find_path(data, "f1_lounge", "f1_stair_e", open).is_empty(), "식당이 잠겨 있으면 동쪽 계단 못 감")
	s.ledger.cash = 1000
	s.try_unlock("f1_mess")
	s.try_unlock("f1_px")
	_c(not RoomRouteService.find_path(data, "f1_lounge", "f1_stair_e", open).is_empty(), "식당·PX 해금 → 동쪽 계단 경로 생김")
	s.try_unlock("b1_training")
	var p2 := RoomRouteService.find_path(data, "b1_training", "f1_lounge", open)
	_c(p2.size() == 6 and p2[1] == "b1_stair_e", "훈련실 → 공용실: 동쪽 계단으로 돌아감 (%s)" % [p2])
	var wp := RoomRouteService.waypoints(data, p, 500.0)
	_c(wp.size() == 3 and wp[0].x > wp[1].x + 100.0 and wp[1].y > wp[0].y, "층 이동 = 계단을 비스듬히 내려감 (위 끝 → 아래 끝)")
	# 7일 동안 대원이 잠긴 방에 들어가지 않음
	var s2 := _sim()
	var bad := []
	var visited := {}
	s2.hour_changed.connect(func(_m):
		for n in s2.npcs.values():
			if n.state != NpcAgent.UNAVAILABLE and not s2.is_unlocked(n.facility):
				bad.append("%s@%s" % [n.id, n.facility])
			if not visited.has(n.id):
				visited[n.id] = {}
			visited[n.id][n.facility] = true)
	s2.skip(7 * 1440)
	_c(bad.is_empty(), "7일 동안 잠긴 방 진입 0회 %s" % [bad.slice(0, 3)])
	var all_move := true
	for id in data.npc_order:
		if visited.get(id, {}).size() < 2:
			all_move = false
	_c(all_move, "모든 대원이 7일 동안 2곳 이상 이동")


func _test_schedules() -> void:
	print("[18] 주간 일정: 요일·시각별 목적지, 잠긴 목적지 대체, 해금 → 생활 변화")
	var s := _sim()
	var kira: NpcAgent = s.npcs.npc_kira
	var dan: NpcAgent = s.npcs.npc_dan
	var mon := 6 * 1440   # 2048-04-13 = 월
	_c(s.clock.weekday(mon) == 0, "2048-04-13 = 월요일")
	_c(s.desired(dan, mon + 9 * 60).facility == "f1_office", "단: 월 09:00 행정실 업무")
	var eat := s.desired(dan, 7 * 60 + 30)
	_c(eat.facility == "f1_lounge" and str(eat.reason).contains("대체"), "식당 잠김 → 아침 식사는 대체 장소 공용실")
	_c(s.desired(kira, 14 * 60).facility == "f1_office", "키라: 훈련실 잠김 → 오후는 원래 업무 (행정실)")
	s.ledger.cash = 1000
	s.try_unlock("f1_mess")
	s.try_unlock("b1_training")
	_c(s.desired(dan, 7 * 60 + 30).facility == "f1_mess", "식당 해금 → 아침 식사 식당")
	_c(s.desired(kira, 14 * 60).facility == "b1_training" and s.desired(kira, 14 * 60).activity == "train", "훈련실 해금 → 키라 오후 훈련 (생활 변화)")
	_c(s.desired(dan, 21 * 60).facility == "b1_quarters", "창고 잠김 → 단 저녁은 숙소")
	s.try_unlock("b2_storage")
	_c(s.desired(dan, 21 * 60).facility == "b1_quarters", "창고만 열고 계단이 잠김 → 갈 수 없어 숙소 그대로")
	s.try_unlock("b2_stair_w")
	_c(s.desired(dan, 21 * 60).facility == "b2_storage", "지하 2층 계단까지 열면 → 단 저녁에 창고 (해금 → 생활 변화)")
	_c(s.desired(dan, 5 * 1440 + 10 * 60).facility == "f1_lounge", "일요일(4/12) 10:00 → 주말 휴식 장소 (요일마다 다른 일정)")
	# 실제로 걸어가는지
	var s2 := _sim()
	s2.skip(5 * 60 + 30)   # 13:30
	_c(s2.npcs.npc_dan.facility == "b1_workshop", "단: 13:00 지나면 오후 업무 장소(작업실)로 이동해 있음 (%s)" % s2.npcs.npc_dan.facility)
	# 에디터 검사
	var open := {}
	for f in data.facility_order:
		if data.facilities[f].initial_open:
			open[f] = true
	var errs := 0
	for id in data.npc_order:
		for e in NpcScheduleResolver.validate(data.schedules[id], data, open):
			if e.level == "error":
				errs += 1
	_c(errs == 0, "기본 일정 6명: 검사 오류 0")
	var bad_sched := {"npc_id": "npc_kira", "weekly_schedule": [
		{"weekday": 0, "start_minute": 60, "end_minute": 120, "target_facility_id": "f1_office", "activity_id": "work"},
		{"weekday": 0, "start_minute": 90, "end_minute": 150, "target_facility_id": "nowhere", "activity_id": "work"},
		{"weekday": 0, "start_minute": 200, "end_minute": 260, "target_facility_id": "f1_mess", "activity_id": "eat"}]}
	var res := NpcScheduleResolver.validate(bad_sched, data, open)
	var txt := "\n".join(res.map(func(e): return e.text))
	_c(txt.contains("없는 시설") and txt.contains("잠김"), "검사: 없는 시설 참조 / 잠긴 목적지 경고")
	var overlap := {"npc_id": "npc_kira", "weekly_schedule": [
		{"weekday": 1, "start_minute": 60, "end_minute": 120, "target_facility_id": "f1_office", "activity_id": "work"},
		{"weekday": 1, "start_minute": 90, "end_minute": 150, "target_facility_id": "f1_lounge", "activity_id": "rest"}]}
	_c("\n".join(NpcScheduleResolver.validate(overlap, data, open).map(func(e): return e.text)).contains("겹침"), "검사: 시간 겹침")


func _test_dialogue() -> void:
	print("[19] 캐릭터 클릭 대화 / 말풍선 엿듣기 / '!' 요청 수락이 서로 구분")
	var s := _sim()
	var d := s.begin_dialogue("npc_kira")
	_c(not d.lines.is_empty() and d.request.is_empty() and s.npcs.npc_kira.state == NpcAgent.PLAYER_DIALOGUE, "키라 클릭 → 직접 대화 (요청 없음)")
	s.skip(30)
	_c(s.npcs.npc_kira.state == NpcAgent.PLAYER_DIALOGUE, "대화 중에는 일정 이동하지 않음")
	s.end_dialogue("npc_kira")
	_c(s.npcs.npc_kira.state != NpcAgent.PLAYER_DIALOGUE, "대화 닫기 → 일정 복귀")
	var q := s.active_request("npc_alma")
	_c(q.get("id", "") == "req_01", "앨마 머리 위 '!' (req_01)")
	_c(s.active_request("npc_ethan").is_empty(), "이선 요청은 4/9 부터 (아직 없음)")
	var d2 := s.begin_dialogue("npc_alma")
	_c(d2.request.get("id", "") == "req_01", "'!' 대원 클릭 → 요청 대화")
	_c(not ("c_ext_escort" in s.available_contracts()), "수락 전: 호위 의뢰 없음")
	var acc := s.accept_request("req_01")
	s.end_dialogue("npc_alma")
	_c(acc.ok and "c_ext_escort" in s.available_contracts(), "수락 → 외부 의뢰 열림")
	_c(not s.accept_request("req_01").ok and s.active_request("npc_alma").is_empty(), "중복 수락 불가, '!' 사라짐")
	s.skip_to_next_day()
	s.skip_to_next_day()
	_c(s.active_request("npc_ethan").get("id", "") == "req_02", "4/9 → 이선 '!' 등장")
	# 대원끼리 대화: 같은 방에서 쉬는 두 대원 (점심 공용실 식사·저녁 잡담 등)
	var s2 := _sim()
	var story_key := ""
	for i in 1440:
		s2.skip(1)
		for ch in s2.chats:
			if ch.story:
				story_key = ch.key
		if story_key != "":
			break
	_c(story_key != "", "스토리 대화 발생 (이선·앨마, %s)" % s2.clock.time_str())
	var o2 := s2.overhear(story_key)
	_c(not o2.is_empty() and o2.story == "story_test_01" and s2.story_seen.has("story_test_01"), "스토리 대화 엿듣기 → 대사 + 스토리 이벤트 기록")
	var normal := {}
	for i in 1440:
		s2.skip(1)
		for ch in s2.chats:
			if not ch.story:
				normal = ch
		if not normal.is_empty():
			break
	_c(not normal.is_empty(), "일반 대화 발생 (%s)" % s2.clock.time_str())
	var o := s2.overhear(normal.get("key", ""))
	_c(not o.is_empty() and not o.lines.is_empty() and o.story == "", "일반 대화 엿듣기 → 대사, 스토리 아님")
	s2.skip(int(normal.end) - s2.minute() + 1)
	_c(s2.chat_by_key(normal.key).is_empty(), "대화는 정해진 시간 뒤 끝남")
	# 일정 이동 시각이 오면 대화가 끊김 (10절 3): 대화를 길게 늘려 두고 다음 이동 시각까지 진행
	var s3 := _sim()
	var ch3 := {}
	while ch3.is_empty() and s3.minute() < 3000:
		s3.skip(1)
		if not s3.chats.is_empty():
			ch3 = s3.chats[0]
	ch3.end = int(ch3.end) + 100000
	s3.skip(1440)
	_c(s3.chat_by_key(ch3.key).is_empty(), "일정 이동 시간이 되면 대원끼리 대화는 끊김")
	var total := 0
	for k in s2.conv_counts:
		total += int(s2.conv_counts[k])
	s2.skip(7 * 1440)
	_c(int(s2.conv_counts.get("conv_story_01", 0)) == 1, "스토리 대화는 최대 1회 (무한 반복 없음)")


func _test_cleaning() -> void:
	print("[20] 일일 오염 / 우클릭 → 청소 → 장소 / 위임")
	var s := _sim()
	var before := s.dirt.size()
	s.skip_to_next_day()
	var n_new := s.dirt.size() - before
	_c(n_new >= 1 and n_new <= 2, "날짜가 바뀌면 오염 1~2건 생성 (%d)" % n_new)
	for dd in s.dirt:
		_c(s.is_unlocked(dd.facility) and s.cleanable(dd.facility), "오염은 해금된 청소 구역에만 (%s)" % dd.facility)
	var s2 := _sim()
	s2.add_dirt("f1_lounge")
	_c(s2.cleanliness.f1_lounge < 90.0, "오염 → 청결도 감소")
	_c(not s2.issue_clean("npc_kira", "f1_mess").ok, "잠긴 방 청소 지시 → 이유 표시하고 실행 안 함")
	_c(not s2.issue_clean("npc_kira", "f1_stair_w").ok, "계단(청소 대상 아님) → 실행 안 함")
	var r := s2.issue_clean("npc_kira", "f1_lounge")
	_c(r.ok and r.executor == "npc_kira", "키라에게 공용실 청소 지시")
	_c(not s2.issue_clean("npc_hana", "f1_lounge").ok, "같은 곳 중복 청소 지시 방지")
	s2.skip(60)
	_c(s2.cleanliness.f1_lounge == 100.0 and s2.dirt_in("f1_lounge").is_empty(), "이동 → 청소 → 오염 제거, 청결 100")
	_c(s2.npcs.npc_kira.command.is_empty(), "청소 끝나면 원래 일정으로 복귀")
	var r2 := s2.issue_clean("npc_dan", "f1_office")
	_c(r2.ok and r2.executor != "npc_dan" and r2.executor in ["npc_hana", "npc_kira"], "단(위임 성향) → 하나·키라 중 한 명이 대신 청소 (%s)" % r2.get("executor", ""))
	var last: Dictionary = s2.cleaning_log[-1]
	_c(last.requested == "npc_dan" and last.executing == r2.executor, "로그: 요청자 단 / 실제 수행자 분리 기록")


func _test_settlement() -> void:
	print("[21] 주간 결산: 지원금·작업 수익이 한 번씩, 시간 건너뛰기 후에도 중복 없음")
	var s := _sim()
	s.inspections["2048-04"].minute = s.clock.month_bounds().y - 1   # 점검 보너스가 이 검사에 섞이지 않게 월말로
	var r := s.issue_job("npc_kira", "c_task_office")
	_c(r.ok, "키라에게 '서류 정리' 작업 지시")
	_c(not s.issue_job("npc_kira", "c_task_workshop").ok, "같은 대원 중복 지시 방지")
	var ext := s.issue_job("npc_dan", "c_ext_supply")
	_c(ext.ok and not ("c_ext_supply" in s.available_contracts()), "외부 의뢰는 한 번 수락하면 목록에서 빠짐")
	s.skip(60 * 3)
	_c(s.npcs.npc_dan.state == NpcAgent.UNAVAILABLE, "외부 의뢰: 정문을 나가 기지 밖 (%s)" % s.npcs.npc_dan.state)
	s.skip(60 * 5)
	_c(s.ledger.pending_total() == 65, "완료 수익은 미지급으로 $65 (25+40)")
	_c(s.npcs.npc_dan.state != NpcAgent.UNAVAILABLE, "외부 의뢰 끝나면 복귀")
	var cash0 := s.ledger.cash
	var sts := []
	s.statement_ready.connect(func(st): sts.append(st))
	s.skip_to_next_week()
	_c(sts.size() == 1 and s.ledger.cash == cash0 + 100 + 65, "1주차 결산: 지원금 $100 + 수익 $65 (잔액 $%d)" % s.ledger.cash)
	_c(s.ledger.pending.is_empty(), "결산 후 미지급 0")
	s.skip(3 * 7 * 1440)
	_c(sts.size() == 4 and s.ledger.settled_weeks == [0, 1, 2, 3], "4주 → 결산 4번, 주마다 1번 (%s)" % [s.ledger.settled_weeks])
	var subs := 0
	for e in s.ledger.entries:
		if e.source == "subsidy":
			subs += 1
	_c(subs == 4, "지원금 4번만")
	_c(s.ledger.settle(1, 100, s.minute(), "").is_empty(), "이미 결산한 주 다시 결산 → 무시")
	_c(not s.ledger.add_pending("job:job_1", "task", 25, "", "", 9), "이미 지급된 작업 수익 다시 넣기 → 무시")


func _test_inspection() -> void:
	print("[22] 장군 점검: 매월 정확히 1회, 보너스는 그 주 결산에만")
	var s := _sim()
	var ins := s.inspection_this_month()
	_c(not ins.is_empty() and int(ins.minute) >= s.minute() and int(ins.minute) < s.clock.month_bounds().y, "4월 점검 시각이 4/7 이후 4월 안에서 정해짐")
	var done := []
	s.inspection_completed.connect(func(rec): done.append(rec.month))
	s.skip_to_next_month()
	_c(done == ["2048-04"], "5/1 까지 → 4월 점검 1회")
	s.skip_to_next_month()
	s.skip_to_next_month()
	_c(done == ["2048-04", "2048-05", "2048-06"], "3달 → 달마다 1회 (%s)" % [done])
	var rec: Dictionary = s.inspections["2048-05"]
	var found_week := -1
	var count := 0
	for st in s.ledger.statements:
		for it in st.items:
			if it.id == "inspection:2048-05":
				found_week = int(st.week)
				count += 1
	_c(count == 1 and found_week == int(rec.week), "5월 점검 보너스는 점검한 주(%d)의 결산에 1번만" % int(rec.week))
	# 달 중간 저장 → 불러오기 후에도 1회
	var s2 := _sim()
	var ins2: Dictionary = s2.inspection_this_month()
	s2.skip(int(ins2.minute) - s2.minute() + 5)
	_c(ins2.done, "점검 시각 지나면 실행")
	var s3 := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s2.to_dict())))
	var again := []
	s3.inspection_completed.connect(func(r2): again.append(r2.month))
	s3.skip(s3.clock.month_bounds(s3.minute()).y - s3.minute() - 1)
	_c(again.is_empty(), "저장 후 불러와도 같은 달 재점검 없음")
	# 청결이 점수에 반영
	var s4 := _sim()
	for f in data.facility_order:
		if s4.cleanable(f):
			s4.cleanliness[f] = 100.0
	s4.debug_inspect_now()
	_c(s4.inspection_this_month().grade == "만족" and s4.ledger.pending_total() == 60, "청결 100 → 만족, 보너스 $60 미지급")


func _test_progression() -> void:
	print("[23] 훈련 · 제작 · 강화 → 전투 데이터")
	var s := _sim()
	_c(not s.issue_train("npc_kira").ok, "훈련실 잠김 → 훈련 불가")
	s.ledger.cash = 500
	s.try_unlock("f1_mess")
	s.try_unlock("b1_training")
	_c(s.issue_train("npc_kira").ok, "훈련 지시")
	s.skip(200)
	_c(s.training_level("a_kira") == 1, "훈련 완료 → 훈련 1단계")
	var base: UnitData = GameData._find(battle.allies, "a_kira")
	var copy := UnitData.new()
	GameData._copy_props(copy, base)
	s.apply_to_ally(copy, base)
	_c(copy.max_hp == base.max_hp + 5, "전투 최대 HP +5 (%d → %d)" % [base.max_hp, copy.max_hp])
	_c(s.weapons_of("a_kira").size() == base.weapons.size(), "무기고: 전투 캐릭터의 초기 무기")
	_c(s.start_craft("r_knife").ok and not s.start_craft("r_pistol").ok, "제작 시작 (작업실은 한 번에 하나)")
	s.skip(125)
	var knife := {}
	for it in s.inventory:
		if it.item == "knife" and it.owner == "":
			knife = it
	_c(not knife.is_empty(), "제작 완료 → 무기고에 단검")
	_c(s.start_enhance(knife.uid).ok, "강화 시작")
	s.skip(65)
	_c(int(knife.plus) == 1, "강화 +1")
	_c(s.equip("a_kira", 1, knife.uid).ok, "키라 보조무기 칸에 단검+1 장착")
	_c(not s.equip("a_kira", 0, "").ok, "주무기는 비울 수 없음")
	s.apply_to_ally(copy, base)
	var w: Dictionary = copy.weapons[1]
	_c(w.id == "knife" and str(w.name).ends_with("+1") and int(w.power_bonus) == int(battle.items.knife.power_bonus) + 1, "전투 무기: 단검 +1, 위력 +1")


func _test_save_load() -> void:
	print("[24] 저장/불러오기: 잠금·달러·날짜·대원 위치·위생·정산/점검·성장 복구")
	var s := _sim()
	s.ledger.cash = 400
	s.try_unlock("f1_mess")
	s.add_dirt("f1_office")
	s.issue_job("npc_kira", "c_task_office")
	s.skip(1440 * 8 + 37)
	var j := JSON.stringify(s.to_dict())
	var t := BaseSim.from_dict(data, battle, JSON.parse_string(j))
	_c(t.ledger.cash == s.ledger.cash and t.clock.label() == s.clock.label(), "달러·날짜 (%s, $%d)" % [t.clock.label(), t.ledger.cash])
	_c(t.unlocked.keys().size() == s.unlocked.keys().size() and t.is_unlocked("f1_mess"), "해금 상태")
	_c(t.dirt.size() == s.dirt.size() and is_equal_approx(t.hygiene_score(), s.hygiene_score()), "위생")
	_c(t.ledger.settled_weeks == s.ledger.settled_weeks and t.ledger.entries.size() == s.ledger.entries.size(), "결산 기록")
	_c(t.inspections.keys() == s.inspections.keys(), "점검 기록")
	var same_pos := true
	for id in s.npcs:
		if s.npcs[id].pos.distance_to(t.npcs[id].pos) > 0.5 or s.npcs[id].facility != t.npcs[id].facility:
			same_pos = false
	_c(same_pos, "대원 위치·시설")
	_c(t.inventory.size() == s.inventory.size(), "무기고")
	s.skip(1440 * 9)
	t.skip(1440 * 9)
	_c(t.ledger.cash == s.ledger.cash and t.dirt.size() == s.dirt.size() and t.clock.label() == s.clock.label(), "불러온 뒤 9일 더 진행해도 원본과 같은 결과 (난수 상태 복구)")


func _test_stairs_walk() -> void:
	print("[25] 계단을 실제로 오르내림 (비스듬히, 꺾인 계단)")
	var s := _sim()
	var dan: NpcAgent = s.npcs.npc_dan
	var diag := 0
	var prev := dan.pos
	for i in 5 * 60 + 30:   # 13:00 오후 업무로 무기고(지하)까지
		s.skip(1)
		var d := dan.pos - prev
		if absf(d.x) > 1.0 and absf(d.y) > 1.0:
			diag += 1
		prev = dan.pos
	_c(diag >= 2, "층을 옮길 때 가로·세로가 같이 바뀜 = 계단 비스듬히 (%d분)" % diag)
	_c(RoomRouteService.flight_left_to_right(1) != RoomRouteService.flight_left_to_right(2), "층마다 계단 방향이 바뀜 (꺾인 계단)")


func _test_fatigue_objects() -> void:
	print("[26] 피로: 깨어 있으면 증가, 침대·의자·소파에서 자야만 회복, 오브젝트마다 회복력 다름")
	var s := _sim()
	var kira: NpcAgent = s.npcs.npc_kira
	var f0 := float(s.cstate(kira).fatigue)
	s.skip(150)   # 10:30 업무
	_c(float(s.cstate(kira).fatigue) > f0, "업무 중 피로 증가 (%.1f → %.1f)" % [f0, float(s.cstate(kira).fatigue)])
	s.skip_to_next_day()
	s.skip(3 * 60)   # 03:00 수면
	_c(kira.seat != "" and s.data.objects[kira.seat].kind == "침대" and s.posture(kira).pose == "lie", "03:00 숙소 침대에 누워 잠 (%s)" % kira.seat)
	var a := float(s.cstate(kira).fatigue)
	s.skip(120)
	_c(float(s.cstate(kira).fatigue) < a, "침대에서 자면 피로 회복 (%.1f → %.1f)" % [a, float(s.cstate(kira).fatigue)])
	var beds := 0
	for n in s.npcs.values():
		if n.seat != "" and s.data.objects[n.seat].kind == "침대":
			beds += 1
	_c(beds == 6, "6명 모두 각자 침대 (같은 침대 둘 없음)")
	# 오브젝트 없이 자면 회복 없음 / 침대(12) vs 의자(3)
	var t := _sim()
	var n: NpcAgent = t.npcs.npc_nikita
	t._release_seat(n)
	n.state = NpcAgent.STAYING
	n.activity = "sleep"
	t.cstate(n).fatigue = 50.0
	for i in 60:
		t._tick_body(n)
	_c(is_equal_approx(float(t.cstate(n).fatigue), 50.0), "오브젝트 없이 자면 피로 그대로")
	n.seat = "obj_chair_o1"
	for i in 60:
		t._tick_body(n)
	var chair := 50.0 - float(t.cstate(n).fatigue)
	t.cstate(n).fatigue = 50.0
	n.seat = "obj_bed_1"
	for i in 60:
		t._tick_body(n)
	var bed := 50.0 - float(t.cstate(n).fatigue)
	_c(is_equal_approx(chair, 3.0) and is_equal_approx(bed, 12.0), "한 시간: 의자 -%.1f / 침대 -%.1f (오브젝트 시트 값)" % [chair, bed])


func _test_hp_medical() -> void:
	print("[27] 전투에서 잃은 체력은 기지로 그대로, 상태 이상은 의무실 치료, 체력은 의무실 휴식으로만")
	var s := _sim()
	var kmax := s.char_max_hp("a_kira")
	s.apply_battle_result({"winner": "ally", "allies": [{"id": "a_kira", "hp": 10, "alive": true, "statuses": ["rallied"]},
		{"id": "a_dan", "hp": 0, "alive": false, "statuses": []}]})
	_c(int(s.cstate_of("a_kira").hp) == 10 and (s.cstate_of("a_kira").statuses as Array).is_empty(), "키라 HP 10/%d 유지, 긍정 상태(독려)는 사라짐" % kmax)
	_c(int(s.cstate_of("a_dan").hp) == 1 and "injured" in s.cstate_of("a_dan").statuses, "쓰러진 단 = HP 1 + 부상")
	_c(s.battle_entry("a_kira").hp == 10 and "injured" in s.battle_entry("a_dan").statuses, "다음 전투에 남은 체력·부상 그대로")
	s.skip(180)
	_c(int(s.cstate_of("a_kira").hp) == 10, "가만히 있으면 체력 회복 안 됨")
	_c(not s.issue_medical("npc_nikita").ok, "치료할 게 없으면 의무실 지시 안 됨")
	_c(s.issue_medical("npc_dan").ok, "단 → 의무실 (치료 후 휴식)")
	s.skip(90)
	_c((s.cstate_of("a_dan").statuses as Array).is_empty(), "치료 끝 → 부상 해제")
	_c(s.npcs.npc_dan.state == NpcAgent.RECOVERING and s.posture(s.npcs.npc_dan).pose == "lie", "의무침대에 누워 휴식")
	var h := float(s.cstate_of("a_dan").hp)
	s.skip(60)
	_c(float(s.cstate_of("a_dan").hp) > h + 7.0, "의무침대 휴식 1시간 = 체력 +8")
	s.skip(8 * 60)
	_c(int(s.cstate_of("a_dan").hp) == s.char_max_hp("a_dan") and s.npcs.npc_dan.command.is_empty(), "체력이 다 차면 일정으로 복귀")


func _test_food_px_affinity() -> void:
	print("[28] 식당 식재료 · PX 선물 · 친밀도")
	var s := _sim()
	_c(not s.buy_food().ok, "식당 잠김 → 식재료 공급 불가")
	s.ledger.cash = 500
	s.try_unlock("f1_mess")
	var c0 := s.ledger.cash
	var f0 := s.food
	_c(s.buy_food().ok and s.ledger.cash == c0 - 20 and s.food == f0 + 12, "식재료 $20 → +12끼")
	var before := s.food
	s.skip(5 * 60)   # 점심 (식당)
	_c(s.food < before, "점심에 식당에서 먹으면 식재료 줄어듦 (%d → %d)" % [before, s.food])
	s.food = 0
	var hungry := s.log_lines.size()
	s.skip(7 * 60)   # 저녁 식사
	_c(s.log_lines.slice(hungry).any(func(l): return str(l).contains("끼니를 걸렀습니다")), "식재료가 없으면 끼니를 거름 (피로 증가)")
	_c(not s.buy_gift("gift_gloves").ok, "PX 잠김 → 구매 불가")
	s.try_unlock("f1_px")
	var dan: NpcAgent = s.npcs.npc_dan
	var a0 := float(s.cstate(dan).affinity)
	_c(s.buy_gift("gift_gloves").ok and int(s.gifts.gift_gloves) == 1, "PX 에서 가죽 장갑 구매")
	var r := s.give_gift("npc_dan", "gift_gloves")
	_c(r.ok and r.liked and is_equal_approx(float(s.cstate(dan).affinity), a0 + 16.0), "단이 제일 좋아하는 가죽 장갑 → 친밀도 +16 (%s)" % r.get("taste", ""))
	var d := s.data
	_c(d.gift_value("gift_gloves", "npc_kira") == 10 and d.gift_value("gift_gloves", "npc_hana") == 5, "같은 선물도 대원마다 상승량 다름 (키라 +10, 하나 기본 +5)")
	_c(d.gift_value("gift_coffee", "npc_nikita") == 8 and d.gift_taste("gift_coffee", "npc_nikita") == "아주 좋아함", "니키타는 캔커피를 아주 좋아함 (+8)")
	_c(d.gift_taste("gift_coffee", "npc_alma") == "별로" and d.gift_value("gift_coffee", "npc_alma") == 1, "앨마는 캔커피가 별로 (+1)")
	var favs := {}
	for nid in d.npc_order:
		var best := ""
		for g in d.px_order:
			if best == "" or d.gift_value(g, nid) > d.gift_value(best, nid):
				best = g
		favs[nid] = best
	_c(favs.npc_dan == "gift_gloves" and favs.npc_kira == "gift_charm" and favs.npc_ethan == "gift_book" and favs.npc_hana == "gift_choco" and favs.npc_nikita == "gift_coffee",
		"대원마다 제일 좋아하는 선물이 다름 (%s)" % favs)
	_c(not s.give_gift("npc_dan", "gift_gloves").ok, "선물이 없으면 못 줌")
	var k0 := float(s.cstate(s.npcs.npc_kira).affinity)
	s.begin_dialogue("npc_kira")
	s.end_dialogue("npc_kira")
	s.begin_dialogue("npc_kira")
	s.end_dialogue("npc_kira")
	_c(is_equal_approx(float(s.cstate(s.npcs.npc_kira).affinity), k0 + 1.0), "하루 첫 대화만 친밀도 +1")
	# 친밀도 대화: 단 친밀도 20 + 장갑 16 (+대화 1) → 30 단계 해금
	var s2 := _sim()
	var dl := s2.begin_dialogue("npc_dan")
	s2.end_dialogue("npc_dan")
	_c(int(dl.affinity_need) == -1 and s2.pending_affinity_talk("npc_dan").is_empty(), "친밀도 21 → 해금된 친밀도 대화 없음 (기본 대사)")
	_c(s2.next_affinity_need("npc_dan") == 30, "다음 대화 기준 30")
	s2._add_affinity(s2.npcs.npc_dan, 10.0)
	_c(s2.log_lines.back().contains("새 대화 해금") and s2.pending_affinity_talk("npc_dan").get("need", 0) == 30, "친밀도 30 도달 → 새 대화 해금 알림·♥")
	dl = s2.begin_dialogue("npc_dan")
	s2.end_dialogue("npc_dan")
	_c(dl.new_talk and int(dl.affinity_need) == 30 and str(dl.lines[0].text).contains("친밀도 30"), "클릭 대화 → 친밀도 30 대화 (%s)" % [dl.lines[0].text if not dl.lines.is_empty() else ""])
	_c(s2.pending_affinity_talk("npc_dan").is_empty(), "본 대화는 ♥ 사라짐")
	s2._add_affinity(s2.npcs.npc_dan, 45.0)   # 76 → 50·70 한꺼번에
	dl = s2.begin_dialogue("npc_dan")
	s2.end_dialogue("npc_dan")
	_c(int(dl.affinity_need) == 50 and s2.pending_affinity_talk("npc_dan").get("need", 0) == 70, "여러 단계 해금 → 낮은 단계부터 차례로")
	s2.begin_dialogue("npc_dan")
	s2.end_dialogue("npc_dan")
	dl = s2.begin_dialogue("npc_dan")
	s2.end_dialogue("npc_dan")
	_c(not dl.new_talk and int(dl.affinity_need) == 70, "다 봤으면 해금된 가장 높은 단계 대화 반복")
	var s3 := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s2.to_dict())))
	_c(s3.pending_affinity_talk("npc_dan").is_empty() and s3.next_affinity_need("npc_dan") == 90, "저장/불러오기 후 본 대화·친밀도 유지")


func _test_battle_rules() -> void:
	print("[29] 전투 발생 규칙 (예시: 6시간마다)")
	var s := _sim()
	var nb := s.next_battle()
	_c(not nb.is_empty() and s.clock.time_str(int(nb.minute)) == "12:00", "다음 전투 12:00 (06:00 기준 6시간 간격)")
	var fired := []
	s.battle_triggered.connect(func(p): fired.append(p.label))
	s.skip(4 * 60)
	_c(fired.size() == 1 and s.pending_battle.get("stage", "") == "stage_01", "12:00 전투 발생 → stage_01 (%s)" % [fired])
	s.skip(7 * 60)
	_c(fired.size() == 1, "전투가 끝나기 전에는 다음 전투 안 생김")
	s.apply_battle_result({"winner": "ally", "allies": []})
	_c(s.pending_battle.is_empty() and s.battle_history.size() == 1, "전투 결과 → 대기 전투 해제, 기록")
	var count := []
	s.battle_triggered.connect(func(_p):
		count.append(1)
		s.pending_battle = {})
	s.skip(24 * 60)
	_c(count.size() == 4, "하루 4번 (00·06·12·18시) (%d)" % count.size())
	var clk := s.clock
	var daily := {"enabled": true, "mode": "daily", "times": ["09:30", "21:00"], "weekdays": [0, 1, 2, 3, 4, 5, 6]}
	_c(BattleRules.fires_at(daily, 9 * 60 + 30, clk) and not BattleRules.fires_at(daily, 9 * 60, clk), "매일 시각 규칙")
	var once := {"enabled": true, "mode": "once", "date": "2048-04-09", "times": ["15:00"], "weekdays": [0, 1, 2, 3, 4, 5, 6]}
	_c(BattleRules.next_fire(once, 0, clk) == 2 * 1440 + 900, "한 번 규칙 (4/9 15:00)")
	var weekend := {"enabled": true, "mode": "interval", "interval_minutes": 360, "anchor": "06:00", "weekdays": [5, 6]}
	_c(s.clock.weekday(BattleRules.next_fire(weekend, 0, clk)) >= 5, "요일 제한 (주말만)")
	_c(BattleRules.describe(s.data.battle_rules[0]) == "06:00 기준 6시간마다", "규칙 설명 (%s)" % BattleRules.describe(s.data.battle_rules[0]))
	_c(BattleRules.next_fire({"enabled": false, "mode": "interval"}, 0, clk) == -1, "꺼진 규칙은 발생 안 함")
