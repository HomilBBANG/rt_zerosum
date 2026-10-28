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
	_test_player_control()
	_test_sortie_lines()
	_test_research()
	_test_skill_tree()
	_test_faith()
	_test_divine()
	_test_skill_tree_editor()


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
	var core_hp := 0
	for n in s.tree_nodes("a_kira"):
		if n.dir == "center" and n.effect == "hp":
			core_hp += int(n.value)
	_c(copy.max_hp == base.max_hp + 5 + core_hp and copy.max_hp == s.char_max_hp("a_kira"), "전투 최대 HP +5 (+ 스킬 트리 중앙 %d) (%d → %d)" % [core_hp, base.max_hp, copy.max_hp])
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
	var beds := {}
	for n in s.npcs.values():
		if n.seat != "" and s.data.objects[n.seat].kind == "침대":
			beds[n.seat] = true
	_c(beds.size() == s.npcs.size(), "%d명 모두 각자 침대 (같은 침대 둘 없음, 로한은 연구실 간이침대)" % s.npcs.size())
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


func _test_player_control() -> void:
	print("[30] 플레이어 조작: 선택한 대원 이동·뛰기·도착 후 행동")
	var s := _sim()
	var dan: NpcAgent = s.npcs.npc_dan
	s.skip(1)
	var start := dan.facility
	var r := s.issue_move("npc_dan", "b1_quarters")
	_c(r.ok and dan.state == NpcAgent.MOVING and dan.dest == "b1_quarters" and not dan.running, "방 클릭 → 숙소로 걸어감 (%s 에서)" % start)
	var walk_left := dan.path.size()
	var r2 := s.issue_move("npc_dan", "b1_quarters", NAN, true)
	_c(r2.ok and dan.running and dan.dest == "b1_quarters", "걷는 중 더블클릭 → 같은 곳으로 뛰기로 바뀜")
	# 걷기 vs 뛰기 도착 시간
	var a := _sim()
	var b := _sim()
	for x in [a, b]:
		x.ledger.cash = 500
		x.try_unlock("b1_training")
		x.skip(1)
	a.issue_move("npc_dan", "b1_training")
	b.issue_move("npc_dan", "b1_training", NAN, true)
	var ta := 0
	var tb := 0
	for m in 120:
		a.skip(1)
		b.skip(1)
		if ta == 0 and a.npcs.npc_dan.state != NpcAgent.MOVING:
			ta = m + 1
		if tb == 0 and b.npcs.npc_dan.state != NpcAgent.MOVING:
			tb = m + 1
	_c(ta > 0 and tb > 0 and tb < ta, "뛰면 더 빨리 도착 (걷기 %d분 / 뛰기 %d분)" % [ta, tb])
	_c(a.npcs.npc_dan.facility == "b1_training" and a.npcs.npc_dan.state == NpcAgent.STAYING and a.npcs.npc_dan.is_holding(), "도착 → 그 방에 머묾 (지시 대기)")
	_c(not b.npcs.npc_dan.running, "도착하면 뛰기 해제")
	var acts := a.room_actions("npc_dan").map(func(x): return x.id)
	_c(acts.has("train"), "훈련실에서 우클릭 행동 = 훈련 %s" % [acts])
	# 숙소에서 잠자기
	s.skip(30)
	_c(dan.facility == "b1_quarters" and dan.state == NpcAgent.STAYING, "숙소 도착")
	acts = s.room_actions("npc_dan").map(func(x): return x.id)
	_c(acts.has("sleep") and acts.has("rest") and acts.has("clean_here"), "숙소 행동 = 잠자기·쉬기·청소 %s" % [acts])
	s.chars[dan.character_id].fatigue = 50.0
	var r3 := s.issue_activity("npc_dan", "sleep")
	s.skip(5)
	_c(r3.ok and dan.activity == "sleep" and s.posture(dan).pose == "lie", "잠자기 → 침대에 누움")
	var f0 := float(s.cstate(dan).fatigue)
	s.skip(30)
	_c(float(s.cstate(dan).fatigue) < f0, "자는 동안 피로 감소 (%.1f → %.1f)" % [f0, float(s.cstate(dan).fatigue)])
	# 잠긴 방·작업 중
	_c(not s.issue_move("npc_dan", "b2_storage").ok, "잠긴 방으로는 못 감")
	var c := _sim()
	c.ledger.cash = 500
	c.try_unlock("b1_training")
	c.skip(1)
	c.issue_train("npc_kira")
	_c(not c.issue_move("npc_kira", "f1_lounge").ok, "훈련 지시 중에는 이동 안 됨 (먼저 그만두기)")
	_c(c.cancel_command("npc_kira").ok and c.npcs.npc_kira.command.is_empty() and c.issue_move("npc_kira", "f1_lounge").ok, "지시 그만두기 → 다시 보낼 수 있음")
	# 다음 일정 블록이 시작되면 일정으로 복귀
	var d := _sim()
	d.skip(1)
	d.issue_move("npc_ethan", "f1_lounge")
	var back := false
	for m in 24 * 60:
		d.skip(1)
		if not d.npcs.npc_ethan.is_holding():
			back = true
			break
	_c(back, "다음 일정 블록이 시작되면 일정대로 움직임")
	var sv := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(a.to_dict())))
	_c(sv.npcs.npc_dan.is_holding() and sv.npcs.npc_dan.facility == "b1_training", "저장/불러오기 후 지시 대기 유지")



func _test_sortie_lines() -> void:
	print("[31] 출정 대기: 상태에 맞는 말풍선 대사 · 출정 불가 대원")
	var lines := SortieLines.read()
	_c(lines.size() >= 20, "출정 대사 파일 읽기 (%d개)" % lines.size())
	var names := {}
	for u in battle.allies:
		names[u.id] = u.display_name
	var ctx := func(cid: String, aff: float, fat: float, hp: float, sts: Array, row: int, dep: Array) -> Dictionary:
		return SortieLines.make_context(cid, str(names.get(cid, cid)), aff, fat, hp, sts, row, dep + [cid], names)
	var all_ok := true
	for u in battle.allies:
		for row in 3:
			if SortieLines.candidates(lines, ctx.call(u.id, 50.0, 20.0, 100.0, [], row, [])).is_empty():
				all_ok = false
	_c(all_ok, "모든 대원이 평범한 상태에서 어느 자리든 할 말이 있음")
	var t := func(c: Dictionary) -> String:
		return str(SortieLines.pick(lines, c).get("text", ""))
	_c(t.call(ctx.call("a_dan", 20.0, 20.0, 30.0, ["injured"], 0, [])) == "이 정도 상처로는 안 멈춰.", "부상 → 그 대원 전용 부상 대사 (공통보다 먼저)")
	_c(t.call(ctx.call("a_kira", 20.0, 85.0, 100.0, [], 1, [])) == "오늘은 집중이 잘 안 돼요…", "피로 85 → 키라 피로 대사 (같은 우선순위면 전용 먼저)")
	_c(t.call(ctx.call("a_kira", 20.0, 95.0, 100.0, [], 1, [])) == "눈이 감겨요… 정말 가야 해요?", "피로 95 → 우선순위 높은 공통 대사")
	_c(t.call(ctx.call("a_alma", 20.0, 20.0, 100.0, [], 1, ["a_hana"])) == "하나, 무리하지 마.", "함께 출정 조건 (하나도 출정)")
	_c(t.call(ctx.call("a_alma", 20.0, 20.0, 100.0, [], 1, [])) != "하나, 무리하지 마.", "함께 출정 대원이 없으면 그 대사 안 나옴")
	_c(t.call(ctx.call("a_nikita", 20.0, 20.0, 100.0, [], 2, [])) == "시야 확보 완료.", "자리 조건 (니키타 후방)")
	var low := SortieLines.pick(lines, ctx.call("a_ethan", 5.0, 20.0, 100.0, [], 1, []))
	_c(str(low.get("text", "")) == "…명령이니까 가는 겁니다.", "친밀도 낮음 → 공통 냉담 대사")
	var custom := [SortieLines.new_line("x", "")]
	custom[0].text = "{name}, 출정!"
	custom[0].status = SortieLines.STATUS_NONE
	var c1: Dictionary = ctx.call("a_hana", 50.0, 0.0, 100.0, [], 0, [])
	_c(SortieLines.format(str(SortieLines.pick(custom, c1).text), custom[0], c1) == "하나, 출정!", "{name} 치환")
	_c(SortieLines.pick(custom, ctx.call("a_hana", 50.0, 0.0, 100.0, ["injured"], 0, [])).is_empty(), "'상태 이상 없음' 조건은 부상이면 안 맞음")
	custom[0].text = ""
	_c(SortieLines.pick(custom, c1).is_empty(), "빈 대사는 고르지 않음")
	# 저장 → 읽기
	var tmp := "user://sortie_lines_test.json"
	SortieLines.write(lines, tmp)
	_c(SortieLines.read(tmp) == lines, "저장 후 다시 읽어도 같음")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# 출정 불가: 외부 의뢰 중인 대원은 편성에서 빠짐 (Game 스크립트를 따로 하나 만들어 시험 — 자동 로드는 건드리지 않음)
	var game: Node = load("res://scripts/game.gd").new()
	var s := _sim()
	game.allies = battle.allies
	game.base = s
	game.campaign = true
	game.reset_formation()
	s.npcs.npc_ethan.state = NpcAgent.UNAVAILABLE
	_c(game.sortie_block_reason("a_ethan") == "외부 의뢰 중" and game.sortie_block_reason("a_dan") == "", "외부 의뢰 중 = 출정 불가")
	game.prune_formation()
	var ids: Array = game.formation.map(func(f): return str(f.unit_id))
	_c(not ids.has("a_ethan") and ids.size() == 5, "출정 대기에 들어가면 출정 불가 대원은 진형에서 빠짐 %s" % [ids])
	s.chars["a_kira"] = {"hp": 10.0, "statuses": ["injured"], "fatigue": 77.0, "affinity": 66.0, "talk_day": -1, "seen_talks": []}
	var st: Dictionary = game.sortie_state("a_kira")
	_c(st.known and is_equal_approx(float(st.fatigue), 77.0) and st.statuses == ["injured"], "출정 대기 대원 상태 = 기지 상태")
	game.campaign = false
	_c(game.sortie_block_reason("a_ethan") == "" and not game.sortie_state("a_kira").known, "전투 테스트(기지 없음)는 모두 출정 가능, 상태 기본값")
	game.free()


func _test_research() -> void:
	print("[32] 연구원 로한: 전투 안 함, 연구 → 무기 제작 해금")
	var s := _sim()
	_c(s.npcs.has("npc_rohan") and not s.is_combatant(s.npcs.npc_rohan), "로한 = 기지 대원, 전투 캐릭터 없음")
	_c(battle.allies.all(func(u): return u.id != "npc_rohan" and u.display_name != "로한"), "로한은 전투 아군 목록에 없음")
	_c(s.is_researcher("npc_rohan") and s.lab_facility() == "b1_lab", "연구원 = 로한, 연구실 기본 개방")
	_c(not s.issue_train("npc_rohan").ok, "로한은 훈련하지 않음")
	_c(not s.recipe_unlocked("r_shotgun") and s.recipe_unlocked("r_knife"), "연구 레시피는 잠김, 기존 레시피는 열림")
	_c(not s.start_craft("r_shotgun").ok, "연구 전에는 산탄총 제작 불가")
	_c(s.research_state("res_mg") == "locked" and not s.start_research("res_mg").ok, "선행 연구(기관단총) 전에는 경기관총 연구 불가")
	var cash := s.ledger.cash
	var r := s.start_research("res_shotgun")
	_c(r.ok and s.ledger.cash == cash - 60 and s.research_state("res_shotgun") == "active", "산탄총 연구 시작 → -$60 (%s)" % r.msg)
	_c(not s.start_research("res_smg").ok, "연구는 한 번에 하나")
	var done := []
	s.research_completed.connect(func(q): done.append(q))
	# 로한이 연구실에서 일할 때만 진행 (점심 이동·잠은 멈춤)
	s.skip(3 * 60)
	var left := int(s.research.get("remaining", 0))
	_c(left > 0 and left < 180, "3시간 지나도 점심 이동 동안은 멈춰서 아직 남음 (%d분)" % left)
	s.skip(24 * 60)
	_c(done == ["res_shotgun"] and s.researched.has("res_shotgun") and s.research.is_empty(), "연구 완료 신호·기록")
	_c(s.recipe_unlocked("r_shotgun") and s.start_craft("r_shotgun").ok, "완료 후 무기고에서 산탄총 제작 가능")
	s.skip(5 * 60)
	_c(s.inventory.any(func(it): return it.item == "shotgun"), "산탄총 제작 완료 → 무기고 보관")
	_c(s.research_state("res_launcher") == "ready", "산탄총 연구 후 유탄발사기 연구 가능")
	var sv := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s.to_dict())))
	_c(sv.researched.has("res_shotgun") and sv.recipe_unlocked("r_shotgun"), "저장/불러오기 후 연구 기록 유지")
	var s2 := _sim()
	s2.ledger.cash = 0
	_c(not s2.start_research("res_shotgun").ok, "달러가 모자라면 연구 못 함")
	var s3 := _sim()
	s3.start_research("res_shotgun")
	s3.npcs.npc_rohan.state = NpcAgent.UNAVAILABLE
	_c(s3.research_pause_reason() != "", "로한이 자리를 비우면 연구 멈춤 (%s)" % s3.research_pause_reason())
	_c(battle.items.has("shotgun") and battle.items.has("launcher"), "새 무기는 밸런스 엑셀 아이템 시트에 있음")


func _test_skill_tree() -> void:
	print("[33] 레벨·경험치·십자형 스킬 트리 (액티브 · 패시브)")
	var s := _sim()
	var cid := "a_dan"
	var lv0 := s.start_level(cid)
	_c(s.char_level(cid) == lv0 and s.skill_points(cid) == 1, "시작 = 캐릭터 시트 레벨 Lv%d, 스킬 포인트 1" % lv0)
	for kind in ["active", "passive"]:
		var nodes := s.tree_nodes(cid, kind)
		var dirs := {}
		for n in nodes:
			dirs[n.dir] = true
		_c(nodes.size() == 13 and dirs.size() == 5, "%s 트리 십자형: 중앙 + 동서남북 × 3단계 = 13칸" % kind)
	_c(s.tree_nodes(cid).size() == 26, "캐릭터마다 트리 두 개 (액티브 · 패시브)")
	for cc in battle.skill_tree:
		var news := (battle.skill_tree[cc] as Array).filter(func(n): return str(n.effect).begins_with("skill:"))
		_c(news.all(func(n): return n.kind == "active" and int(n.tier) == s.max_tier(cc, n.dir, "active")), "%s: 새 스킬은 액티브 갈래 끝에만 (%d개)" % [cc, news.size()])
	_c(s.has_skill(cid, "dan_a_core") and s.has_skill(cid, "dan_p_core") and s.skill_state(cid, "dan_p_core") == "learned", "두 트리 중앙은 처음부터 배움")
	_c(s.skill_state(cid, "dan_a_n2") == "no_level" and s.skill_state(cid, "dan_a_n3") == "no_level", "레벨 모자라면 '경험 부족' (2·3단계)")
	_c(s.skill_state(cid, "dan_p_n1") == "ready" and s.skill_state(cid, "dan_a_e1") == "ready", "1단계는 바로 배울 수 있음 (두 트리)")
	var r := s.learn_skill(cid, "dan_p_n1")
	_c(r.ok and s.skill_points(cid) == 0 and s.skill_state(cid, "dan_a_e1") == "no_point", "포인트는 공용: 패시브에 쓰면 액티브는 포인트 부족")
	# 레벨 업
	var ups := s.add_xp(cid, s.xp_need(cid))
	_c(ups == 1 and s.char_level(cid) == lv0 + 1 and s.skill_points(cid) == 1, "경험치 채우면 레벨 업 + 포인트 1")
	_c(s.skill_state(cid, "dan_a_n2") == "no_level", "2단계는 시작+2 레벨부터")
	s.add_xp(cid, 10000)
	_c(s.char_level(cid) >= lv0 + 6, "경험치 많이 → 여러 레벨 (Lv%d)" % s.char_level(cid))
	_c(s.skill_state(cid, "dan_a_s2") == "need_prev", "갈래 안에서는 앞 단계 먼저")
	_c(s.skill_state(cid, "dan_a_n1") == "need_prev" or s.skill_state(cid, "dan_a_n1") == "ready", "액티브 1단계의 앞 = 액티브 중앙")
	_c(s.learn_skill(cid, "dan_a_n1").ok and s.learn_skill(cid, "dan_a_n2").ok and s.learn_skill(cid, "dan_a_n3").ok, "액티브 북(화력) 갈래 끝까지")
	s.learn_skill(cid, "dan_a_e1")
	s.learn_skill(cid, "dan_a_e2")
	_c(s.skill_state(cid, "dan_a_e3") == "capped", "갈래 끝은 트리마다 하나 (액티브 북 끝 → 액티브 동 끝 막힘)")
	s.learn_skill(cid, "dan_p_e1")
	s.learn_skill(cid, "dan_p_e2")
	_c(s.skill_state(cid, "dan_p_e3") == "ready", "패시브 트리 갈래 끝은 따로 (액티브 끝과 무관)")
	_c(s.learn_skill(cid, "dan_p_e3").ok, "패시브 동 끝 배움")
	# 전투 반영
	var base: UnitData = GameData._find(battle.allies, cid)
	var copy := UnitData.new()
	GameData._copy_props(copy, base)
	s.apply_to_ally(copy, base)
	_c(copy.level == s.char_level(cid), "전투 레벨 = 기지 레벨")
	_c(copy.skill_ids.has("brutal_strike") and copy.skill_ids.find("brutal_strike") < copy.skill_ids.find("ultimate"), "액티브 북 끝 '강타' → 전투 스킬에 추가 (필살기 앞) %s" % [copy.skill_ids])
	_c(copy.power_bonus == 1 and int(copy.skill_power.get("heavy_attack", 0)) == 5, "무기 숙련(패시브) 위력 +1, 강공 단련·숙달(액티브) 강공격 +5")
	_c(copy.speed == base.speed + 3 and copy.ap_recovery == base.ap_recovery + 1, "패시브 동 갈래: 속도 +1 +2, AP 회복 +1")
	_c(not base.skill_ids.has("brutal_strike") and base.power_bonus == 0, "원본 캐릭터 데이터는 그대로 (복제본에만)")
	# 위력 계산
	var a: ActionData = battle.actions["heavy_attack"]
	var me := UnitRuntime.new()
	me.data = copy
	var tgt := UnitRuntime.new()
	var td := UnitData.new()
	tgt.data = td
	var me0 := UnitRuntime.new()
	me0.data = base
	var d1 := ActionResolver.compute_damage(a, me, tgt, null)
	var d0 := ActionResolver.compute_damage(a, me0, tgt, null)
	_c(d1 > d0, "배운 스킬로 강공격 피해 증가 (%d → %d)" % [d0, d1])
	# 저장·초기화
	var sv := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s.to_dict())))
	_c(sv.char_level(cid) == s.char_level(cid) and sv.has_skill(cid, "dan_a_n3"), "저장/불러오기 후 레벨·스킬 유지")
	var pts := s.skill_points(cid)
	_c(s.reset_skills(cid, "active").ok and s.skill_points(cid) == pts + 5 and not s.has_skill(cid, "dan_a_n1") and s.has_skill(cid, "dan_p_e3"), "액티브만 초기화 → 액티브 포인트만 돌려받음 (패시브 유지)")
	_c(s.reset_skills(cid).ok and s.skill_points(cid) == pts + 9 and not s.has_skill(cid, "dan_p_n1"), "전체 초기화 → 포인트 전부 돌려받음")
	# 전투 결과 → 경험치
	var s2 := _sim()
	s2.apply_battle_result({"winner": "ally", "allies": [{"id": "a_kira", "hp": 30, "alive": true, "statuses": []}]})
	_c(s2.char_xp("a_kira") == data.inum("xp_win", 100) or s2.char_level("a_kira") > s2.start_level("a_kira"), "승리 → 출전 대원 경험치")
	_c(s2.char_xp("a_dan") == 0 and s2.char_level("a_dan") == s2.start_level("a_dan"), "출전 안 한 대원은 경험치 없음")
	_c(battle.warnings.is_empty(), "밸런스 데이터 참조 오류 없음 %s" % [battle.warnings])


func _test_faith() -> void:
	print("[34] 신앙: 믿는 신에 따라 다른 신앙 스킬 (임시 데이터)")
	var s := _sim()
	_c(battle.gods.size() >= 2, "신 종류 %d개" % battle.gods.size())
	_c(s.god_of("a_dan") != "" and s.god_of("a_dan") != s.god_of("a_kira"), "캐릭터마다 믿는 신 (단 %s / 키라 %s)" % [s.god_of("a_dan"), s.god_of("a_kira")])
	var dan := s.faith_skill_list("a_dan").map(func(x): return x.id)
	var kira := s.faith_skill_list("a_kira").map(func(x): return x.id)
	_c(not dan.is_empty() and dan.all(func(x): return not kira.has(x)), "신이 다르면 배울 수 있는 스킬이 다름")
	_c(s.faith_state("a_dan", kira[0]) == "other_god" and not s.learn_faith_skill("a_dan", kira[0]).ok, "다른 신의 스킬은 못 배움")
	var f0 := s.faith("a_dan")
	_c(f0 == int(battle.char_faith.a_dan.faith), "시작 신앙도 = faith.json believers (%d)" % f0)
	var hi: Dictionary = s.faith_skill_list("a_dan").back()
	_c(s.faith_state("a_dan", hi.id) == "no_faith", "신앙도 모자라면 '신앙 부족'")
	var lo: Dictionary = s.faith_skill_list("a_dan").front()
	_c(s.learn_faith_skill("a_dan", lo.id).ok and s.has_faith_skill("a_dan", lo.id), "신앙도 충분하면 배움 (포인트 안 씀, 스킬 포인트 %d)" % s.skill_points("a_dan"))
	s.apply_battle_result({"winner": "ally", "allies": [{"id": "a_dan", "hp": 30, "alive": true, "statuses": []}]})
	_c(s.faith("a_dan") == f0 + data.inum("faith_battle", 5), "출전하면 신앙도 +%d" % data.inum("faith_battle", 5))
	var base: UnitData = GameData._find(battle.allies, "a_dan")
	var copy := UnitData.new()
	GameData._copy_props(copy, base)
	s.apply_to_ally(copy, base)
	_c(copy.power_bonus >= 1, "신앙 스킬 효과 → 전투 복제본 (위력 +%d)" % copy.power_bonus)
	var sv := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s.to_dict())))
	_c(sv.faith("a_dan") == s.faith("a_dan") and sv.has_faith_skill("a_dan", lo.id), "저장/불러오기 후 신앙 유지")


## 신 해금 캐릭터 (하나 = 대지모 테라, 잠김 — 미션 '민간인 호위' 의뢰를 끝내면 해금 · 임시 데이터) · 기적
func _test_divine() -> void:
	print("[34b] 신 해금 캐릭터 · 기적 · 해금 조건 (미션 완료)")
	var s := _sim()
	_c(s.divine_state("a_nikita") == "" and s.divine_state("a_dan") == "", "니키타·단 = 신 아님")
	_c(s.divine_state("a_hana") == "locked" and not s.is_divine("a_hana"), "하나 = 신 해금 캐릭터 · 잠김")
	var cond: Dictionary = battle.divine.a_hana.condition
	_c(cond.type == "quest" and cond.target == "contract:c_ext_escort", "해금 조건 = 미션 완료 (의뢰 민간인 호위)")
	var mid: String = s.miracle_list("a_hana")[0].id
	_c(s.miracle_state("a_hana", mid) == "locked" and not s.learn_miracle("a_hana", mid).ok, "잠긴 동안 기적 못 배움")
	var got := []
	s.divine_revealed.connect(func(c): got.append(c))
	# 다른 의뢰를 끝내도 그대로, 그 의뢰를 끝내면 해금
	s.jobs.append({"uid": "t1", "contract": "c_ext_supply", "npc": "npc_dan", "state": "assigned", "minute": 0})
	s._complete_job("t1", s.npcs.npc_dan)
	_c(not s.is_divine("a_hana") and not s.quest_done("contract:c_ext_escort") and s.quest_done("contract:c_ext_supply"), "다른 의뢰(보급품 운반) 완료 → 아직 잠김")
	s.jobs.append({"uid": "t2", "contract": "c_ext_escort", "npc": "npc_kira", "state": "assigned", "minute": 0})
	_c(not s.quest_done("contract:c_ext_escort"), "맡기기만 하면 미완료")
	s._complete_job("t2", s.npcs.npc_kira)
	_c(s.is_divine("a_hana") and got == ["a_hana"] and s.divine_god("a_hana").name == battle.gods.terra.name, "민간인 호위 완료 → 하나 정체 해금 (테라), 알림 1번")
	var need := int(s.miracle_list("a_hana")[0].need)
	_c(s.miracle_state("a_hana", mid) == ("ready" if s.faith("a_hana") >= need else "no_faith"), "해금 뒤 기적 = 신성도로 (지금 %d, 필요 %d)" % [s.faith("a_hana"), need])
	s.add_faith("a_hana", need)
	_c(s.learn_miracle("a_hana", mid).ok and s.miracle_state("a_hana", mid) == "learned", "신성도 충분 → 기적 배움")
	var hi: Dictionary = s.miracle_list("a_hana").back()
	_c(s.miracle_state("a_hana", hi.id) == "no_faith", "신성도 모자라면 '신성도 부족'")
	var base: UnitData = GameData._find(battle.allies, "a_hana")
	var copy := UnitData.new()
	GameData._copy_props(copy, base)
	var hp0 := s.char_max_hp("a_hana")
	s.apply_to_ally(copy, base)
	_c(copy.max_hp >= base.max_hp + 10, "기적 효과 → 전투 복제본 (최대 HP %d → %d)" % [base.max_hp, copy.max_hp])
	var sv := BaseSim.from_dict(data, battle, JSON.parse_string(JSON.stringify(s.to_dict())))
	_c(sv.is_divine("a_hana") and sv.miracle_state("a_hana", mid) == "learned", "저장/불러오기 후 정체·기적 유지")
	_c(not s.unlock_divine("a_hana").ok and not s.unlock_divine("a_nikita").ok, "이미 해금 · 신 아님 = 직접 해금 실패")
	# 미션 종류: 전투 승리 · 연구
	var st: String = battle.stage_order[0]
	_c(not s.quest_done("stage:" + st), "전투 미션: 이기기 전 미완료")
	s.battle_history.append({"stage": st, "winner": "enemy"})
	_c(not s.quest_done("stage:" + st), "져도 미완료")
	s.battle_history.append({"stage": st, "winner": "ally"})
	_c(s.quest_done("stage:" + st), "이기면 완료")
	var rq: String = data.research_order[0]
	_c(not s.quest_done("research:" + rq), "연구 미션: 완료 전")
	s.researched[rq] = true
	_c(s.quest_done("research:" + rq) and not s.quest_done("nope") and not s.quest_done("contract:없음"), "연구 완료 / 잘못된 미션 = 미완료")
	# 다른 조건 종류
	_c(s.cond_met({"type": "level", "value": s.char_level("a_dan")}, "a_dan") and not s.cond_met({"type": "level", "value": s.char_level("a_dan") + 1}, "a_dan"), "조건: 레벨 이상")
	_c(s.cond_met({"type": "day", "value": 1}, "a_dan") and not s.cond_met({"type": "day", "value": 99}, "a_dan"), "조건: n일차부터")
	_c(not s.cond_met({"type": "manual", "value": 0}, "a_dan") and s.cond_met({"type": "always", "value": 0}, "a_dan"), "조건: 직접(자동 해금 안 됨) · 처음부터")
	var names := UnlockCond.mission_names(data, battle)
	_c(UnlockCond.describe(cond, names) == "미션 완료: 의뢰 민간인 호위" and UnlockCond.norm({"type": "zzz"}).type == "manual", "조건 설명 '%s' · 모르는 조건 = 직접 해금" % UnlockCond.describe(cond, names))
	_c(UnlockCond.missions(data, battle).size() == data.job_order.size() + battle.stage_order.size() + data.research_order.size(), "미션 목록 = 의뢰 + 전투 스테이지 + 연구")
	# 처음부터 해금 (데이터는 그대로 두고 복사본으로)
	var b2 := GameData.load_from()
	b2.divine["a_kira"] = {"god": "veyra", "unlocked": true, "condition": {"type": "manual", "value": 0}}
	var s3 := BaseSim.create(data, b2)
	_c(s3.is_divine("a_kira") and s3.divine_state("a_kira") == "unlocked", "'이미 해금됨' = 새 게임부터 기적 탭")
	var fd := FaithData.read()
	_c(FaithData.check(fd, battle.char_faith, battle.actions).errors.is_empty(), "faith.json 신 해금·기적 검사 오류 없음")


func _test_skill_tree_editor() -> void:
	print("[35] 스킬 트리 노드 데이터 (data/skill_tree.json) · 에디터 '스킬 트리' 탭")
	var nodes := SkillTreeData.read()
	_c(nodes.size() == 156, "JSON 노드 %d개 (6명 × 액티브·패시브 × 13)" % nodes.size())
	var allies_arr: Array = []
	allies_arr.assign(battle.allies)
	var res := SkillTreeData.check(nodes, allies_arr, battle.actions)
	_c(res.errors.is_empty(), "기본 데이터 검사 오류 없음 %s" % [res.errors])
	# 저장 → 다시 읽기 같음
	var tmp := "user://skill_tree_test.json"
	_c(SkillTreeData.write(nodes, tmp) == OK and JSON.stringify(SkillTreeData.read(tmp)) == JSON.stringify(SkillTreeData.sorted(nodes)), "저장 → 다시 읽기 그대로")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
	# 검사가 잡는 것
	var bad: Array = JSON.parse_string(JSON.stringify(nodes))
	bad[1].effect = "skill_power:nope"
	bad[14].id = bad[15].id
	var gap := SkillTreeData.new_node("a_dan", "active", "n", 4)
	gap.id = "gap_test"
	var ok_gap: Array = bad.filter(func(n): return not (n.char == "a_dan" and n.kind == "active" and n.dir == "n" and int(n.tier) == 3))
	ok_gap.append(gap)
	var r2 := SkillTreeData.check(ok_gap, allies_arr, battle.actions)
	var txt := "\n".join(r2.errors)
	_c("nope" in txt and "두 번" in txt and "3단계가 비었" in txt, "검사: 없는 스킬 · 겹친 id · 빈 단계를 잡음")
	_c(SkillTreeData.auto_desc("skill_power:heavy_attack", 3, battle.actions) == "강공격 위력 +3" and SkillTreeData.auto_desc("hp", 6, battle.actions) == "최대 HP +6", "자동 설명")
	# 갈래를 4단계로 늘린 트리도 게임 규칙대로 (갈래 끝 = 4단계)
	var g2 := GameData.load_from()
	var four := SkillTreeData.new_node("a_dan", "passive", "s", 4)
	four.id = "dan_p_s4"
	four.level = 5
	g2.skill_tree["a_dan"].append(four)
	var s := BaseSim.create(data, g2)
	s.add_xp("a_dan", 100000)
	_c(s.max_tier("a_dan", "s", "passive") == 4, "남 갈래 4단계")
	for id in ["dan_p_s1", "dan_p_s2", "dan_p_s3"]:
		s.learn_skill("a_dan", id)
	_c(s.skill_state("a_dan", "dan_p_s3") == "learned" and s.skill_state("a_dan", "dan_p_s4") == "ready", "3단계는 이제 갈래 끝이 아님, 4단계 배울 수 있음")
	s.learn_skill("a_dan", "dan_p_s4")
	s.learn_skill("a_dan", "dan_p_e1")
	s.learn_skill("a_dan", "dan_p_e2")
	_c(s.skill_state("a_dan", "dan_p_e3") == "capped", "4단계 갈래 끝을 배우면 다른 갈래 끝 막힘")
	# 전투 전용 상태 이상은 기지로 안 넘어감
	var s3 := _sim()
	s3.apply_battle_result({"winner": "ally", "allies": [{"id": "a_kira", "hp": 20, "alive": true, "statuses": ["bleed", "stun", "injured"]}]})
	_c(s3.cstate_of("a_kira").statuses == ["injured"], "전투 끝: 출혈·기절은 사라지고 부상만 기지로 %s" % [s3.cstate_of("a_kira").statuses])
	# 신앙 데이터 (data/faith.json)
	var fd := FaithData.read()
	_c(fd.gods.size() == 4 and fd.skills.size() == 16 and battle.gods.size() == 4, "faith.json: 신 4 · 신앙 스킬 16")
	_c(FaithData.check(fd, battle.char_faith, battle.actions).errors.is_empty(), "신앙 데이터 검사 오류 없음")
	var tmpf := "user://faith_test.json"
	FaithData.write(fd, tmpf)
	_c(JSON.stringify(FaithData.by_god(FaithData.read(tmpf))) == JSON.stringify(FaithData.by_god(fd)), "신앙 저장 → 다시 읽기 그대로")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmpf))
	# 에디터 패널: 노드 추가 · 삭제(뒤 단계 당김)
	var panel: Control = load("res://addons/rtz_skill_editor/skill_editor_panel.gd").new()
	panel._ready()   # 에디터 밖(테스트)이라 트리에 붙이지 않고 화면만 만듦
	_c(panel.nodes.size() == 156 and panel.cid == "a_dan", "에디터 탭 열림 (노드 %d개, %s)" % [panel.nodes.size(), panel.cid])
	panel.kind = "passive"
	panel._add_node("s", 4)
	var added: Dictionary = panel._node(panel.sel)
	_c(added.dir == "s" and int(added.tier) == 4 and added.id == "dan_p_s4" and int(added.level) == int(panel._at("s", 3).level) + 2, "'+' 칸 → 남 4단계 추가 (id %s, 필요 레벨 앞 단계 +2)" % added.id)
	panel._delete("dan_p_s2")
	_c(panel._at("s", 2).id == "dan_p_s3" and panel._at("s", 3).id == "dan_p_s4" and panel._at("s", 4).is_empty(), "중간 단계 삭제 → 바깥 단계가 안으로 당겨짐")
	panel._swap("dan_p_s3", 1)
	_c(panel._at("s", 3).id == "dan_p_s3", "단계 자리 바꾸기")
	# 에디터 신앙: 신 추가 → 신앙 스킬 추가 → 신 삭제(그 스킬도)
	panel.kind = "faith"
	panel._rebuild()
	var g0: int = panel.faith.gods.size()
	panel._add_god()
	var gid: String = panel.god_sel
	panel._add_faith_skill()
	panel._add_faith_skill()
	var mine: Array = panel._god_skills()
	_c(panel.faith.gods.size() == g0 + 1 and mine.size() == 2 and int(mine[1].need) == int(mine[0].need) + 20, "에디터: 신 추가 + 신앙 스킬 2개 (필요 신앙도 20 간격)")
	_c(panel.faith_box.visible and not panel.canvas.visible, "신앙 모드: 신 목록·신앙 스킬 목록")
	panel._delete_god()
	_c(panel._god(gid).is_empty() and not panel.faith.skills.any(func(f): return f.god == gid), "신 삭제 → 그 신의 신앙 스킬도 삭제")
	# 에디터 상태 이상: 스킬에 달기 · 빼기
	panel.kind = "status"
	panel.skill_sel = "heavy_attack"
	panel._rebuild()
	_c(panel.status_box.visible and panel._skill_statuses("heavy_attack").is_empty(), "상태 이상 모드: 강공격에는 아직 없음")
	panel.sstat.append(SkillStatusData.new_entry("heavy_attack", "burn"))
	panel.sstat.append(SkillStatusData.new_entry("heavy_attack", "blind"))
	panel._rebuild()
	var us: Dictionary = panel._users("rend")
	_c(panel._skill_statuses("heavy_attack").size() == 2 and us.monster.has("구울"), "강공격에 화상·실명 2개 · 할퀴기 쓰는 쪽 = 구울")
	_c(SkillStatusData.check(panel.sstat, battle.actions).errors.is_empty(), "검사 통과")
	var bad_e := SkillStatusData.new_entry("move", "stun")
	_c(not SkillStatusData.check(panel.sstat + [bad_e], battle.actions).errors.is_empty(), "이동에는 못 닮 (검사 오류)")
	var by := SkillStatusData.by_skill(panel.sstat)
	_c(by.heavy_attack.size() == 2 and by.heavy_attack[0].id == "burn", "스킬별로 묶기 → ActionData.statuses 형식")
	panel.sstat.erase(panel._skill_statuses("heavy_attack")[0])
	_c(panel._skill_statuses("heavy_attack").size() == 1, "빼기")
	# 몬스터 스킬 (data/monster_skills.json)
	var md := MonsterSkillData.read()
	_c(md.skills.size() == 4 and md.kits.ghoul.has("rend") and battle.monsters.ghoul.skill_ids == md.kits.ghoul, "monster_skills.json: 전용 스킬 4 · 구울 스킬 목록 = kits")
	_c(battle.actions.has("hamstring") and battle.actions.hamstring.status_ids() == ["root"], "몬스터 전용 스킬도 스킬로 읽힘 (+ 상태 이상)")
	panel.kind = "monster"
	panel.mon_sel = "wolf"
	panel._rebuild()
	_c(panel.monster_box.visible and panel._kit() == ["basic_attack", "heavy_attack", "hamstring", "sand_kick", "ultimate"], "몬스터 모드: 늑대 스킬 목록")
	panel._new_monster_skill()
	var nid: String = panel.mskill_sel
	var nm: Dictionary = panel._mskill(nid)
	nm.power = 13
	panel._sync_mskill(nm)
	_c(panel._kit().has(nid) and panel.actions[nid].power == 13, "새 몬스터 스킬 → 늑대 목록에 들어감 (%s)" % nid)
	panel.mskill_sel = "sand_kick"
	panel._kit_move(-1)
	_c(panel._kit().find("sand_kick") == 2, "스킬 순서 위로")
	var mchk := MonsterSkillData.check(panel.mdata, panel.sheet_skill_ids, panel.monsters, panel._ai_uses())
	_c(mchk.errors.is_empty() and "\n".join(mchk.notes).contains(nid), "검사: 새 스킬은 'AI 가 안 씀' 주의 %s" % [mchk.errors])
	# AI 그래프에 끼우기 (파일은 안 건드리고 복사본으로)
	var g: Dictionary = AIGraph.load_graph("aggressive").duplicate(true)
	_c(AIGraph.insert_skill(g, nid, "hp_pct_low") and AIGraph.skills_used(g).has(nid) and not AIGraph.insert_skill(g, nid, "hp_pct_low"), "AI 그래프에 '스킬 사용' 노드 끼움 (두 번은 안 들어감)")
	var ult_next := ""
	var ult_id := ""
	for n in g.nodes:
		if n.type == "act_skill" and n.params.skill == "ultimate":
			ult_id = n.id
	for c in g.connections:
		if c.from == ult_id and int(c.port) == 0:
			ult_next = c.to
	_c(ult_next == "sk_" + nid, "필살기 다음 칸에 들어감")
	_c(not MonsterSkillData.check({"skills": [MonsterSkillData.new_skill("heal")], "kits": {}}, battle.actions.keys(), battle.monsters).errors.is_empty(), "검사: 엑셀 스킬과 같은 id 는 오류")
	panel.free()
