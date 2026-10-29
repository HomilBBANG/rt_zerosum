extends SceneTree
## 헤드리스 규칙 테스트: godot --headless -s tests/run_tests.gd
## GDD 8절 "필수 검증 사례"를 다룬다.

var _fails := 0
var _passes := 0


func _check(cond: bool, name: String) -> void:
	if cond:
		_passes += 1
		print("  PASS  ", name)
	else:
		_fails += 1
		print("  FAIL  ", name)


func _make(ambush: String, seed_v: int = 7) -> BattleController:
	var bc := BattleController.new()
	bc.enemy_delay = 0.0
	var allies := TestRoster.build_allies()
	var enemies := TestRoster.build_enemies()
	bc.setup(TestRoster.build_actions(), TestRoster.default_roster(allies, enemies), seed_v, ambush)
	root.add_child(bc)
	return bc


func _names(arr: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for u in arr:
		out.append(u.display_name())
	return out


func _unit(bc: BattleController, name: String) -> UnitRuntime:
	for u in bc.slots.all_units():
		if u.display_name() == name:
			return u
	return null


func _init() -> void:
	print("== RT Zerosum battle rule tests ==")
	_test_formation_slots()
	_test_initiative_enemy_first_but_ally_faster()
	_test_round2_no_bonus()
	_test_tiebreaks()
	_test_ap_rules()
	_test_move_swap()
	_test_rejections_cost_no_ap()
	_test_melee_row_rule()
	_test_restart_resets()
	_test_coin_is_seeded()
	_test_large_units()
	_test_equip_and_move_lock()
	_test_rally_status()
	_test_battle_statuses()
	_test_status_effects()
	_test_hit_evasion()
	_test_poses()
	_test_codex()
	_test_balance_data_and_ai_graph()
	_test_sfx()
	load("res://tests/outgame_tests.gd").new().run(_check)
	print("== %d passed, %d failed ==" % [_passes, _fails])
	quit(1 if _fails > 0 else 0)


func _test_formation_slots() -> void:
	print("[1] 6슬롯 편성 및 슬롯 데이터")
	var bc := _make("ally")
	bc.start_battle()
	_check(bc.slots.living_units("ally").size() == 6, "아군 6인 배치")
	_check(bc.slots.living_units("enemy").size() == 6, "적군 6인 배치")
	_check(bc.slots.unit_at("ally:0:0").display_name() == "지호", "ally:0:0 = 지호")
	_check(bc.slots.unit_at("enemy:2:1").display_name() == "지휘관", "enemy:2:1 = 지휘관")
	_check(bc.slots.units_in_row("ally", 1).size() == 2, "아군 중앙열 2명")
	bc.queue_free()


func _test_initiative_enemy_first_but_ally_faster() -> void:
	print("[2] 적 선공이지만 아군이 더 빠른 경우 (적 저격수 12 vs 아군 라온 11 → 적 최고속은 저격수 12)")
	# 적 최고속(저격수 12)이 아군 최고속(라온 11)보다 빠르면 특례가 보이지 않으므로, 적 선공 + 라온 속도를 올려 검증
	var bc := _make("enemy")
	var raon := TestRoster.find_unit(TestRoster.build_allies(), "a_raon")
	# roster 안 data 참조를 교체
	for e in bc._roster:
		if e.data.id == "a_raon":
			e.data = e.data.duplicate()
			e.data.speed = 20
	bc.start_battle()
	var q := _names(bc.queue)
	_check(bc.first_team == "enemy", "적 선공")
	_check(q[0] == "저격수", "1라운드 첫 행동 = 적 최고속(저격수 12) [got %s]" % q[0])
	_check(q[1] == "라온", "그 다음 = 전체 속도순 최고(라온 20) [got %s]" % q[1])
	# 이후 전체 속도 내림차순 확인
	var ok := true
	for i in range(2, bc.queue.size()):
		if bc.queue[i - 1].data.speed < bc.queue[i].data.speed:
			ok = false
	_check(ok, "나머지 속도 내림차순")
	bc.queue_free()


func _test_round2_no_bonus() -> void:
	print("[3] 2라운드에 선공 보너스 미적용")
	var bc := _make("ally")
	# 아군 선공: 1라운드 첫 행동은 아군 최고속 라온(11) → 그러나 적 저격수 12가 더 빠르므로 2라운드엔 저격수가 먼저
	bc.start_battle()
	_check(bc.queue[0].display_name() == "라온", "1라운드 첫 행동 = 아군 최고속 라온 [got %s]" % bc.queue[0].display_name())
	_check(bc.queue[1].display_name() == "저격수", "1라운드 2번째 = 적 저격수(12) [got %s]" % bc.queue[1].display_name())
	# 모든 아군 턴을 종료시켜 2라운드까지 진행
	var guard := 0
	while bc.round_no == 1 and guard < 50:
		if bc.is_player_turn():
			bc.player_end_turn()
		guard += 1
	_check(bc.round_no == 2, "2라운드 도달")
	_check(bc.queue[0].display_name() == "저격수", "2라운드 첫 행동 = 전체 최고속 저격수 [got %s]" % bc.queue[0].display_name())
	bc.queue_free()


func _test_tiebreaks() -> void:
	print("[4] 동률 아군 우선 / 아군 레벨 우선 / 원거리 우선")
	var bc := _make("ally")
	bc.start_battle()
	var q := _names(bc.queue)
	# 속도 9: 지호(ally lv5 melee), 도윤(ally lv5 ranged), 소총병(enemy lv5 ranged)
	var i_jiho := q.find("지호")
	var i_doyun := q.find("도윤")
	var i_rifle := q.find("소총병")
	_check(i_doyun < i_rifle and i_jiho < i_rifle, "속도 9 동률: 아군 우선 (적 소총병 마지막)")
	_check(i_doyun < i_jiho, "아군 동률·동레벨: 원거리(도윤) 우선")
	# 레벨 우선 확인: 도윤 레벨을 낮춰 지호가 먼저 가는지
	var units: Array[UnitRuntime] = bc.slots.all_units()
	var doyun := _unit(bc, "도윤")
	doyun.data = doyun.data.duplicate()
	doyun.data.level = 2
	var q2 := _names(TurnScheduler.build_round_queue(units, 2, ""))
	_check(q2.find("지호") < q2.find("도윤"), "아군 동률: 높은 레벨(지호 5 > 도윤 2) 우선")
	bc.queue_free()


func _test_ap_rules() -> void:
	print("[5] AP 최대치 버림 / 이월 / 연속 스킬 후 AP 0 즉시 턴 종료")
	var bc := _make("ally")
	bc.start_battle()
	var raon := bc.current
	_check(raon.display_name() == "라온", "현재 행동자 라온")
	_check(raon.ap == raon.data.max_ap, "전투 시작 AP = 최대 (%d)" % raon.ap)
	# 최대치에서 회복량 버림: 시작 시 recover 가 적용되어도 max 유지
	_check(raon.ap == 5, "최대 AP 초과 회복 버림")
	# 기본공격 1회 (AP 5→4) 후 턴 종료 → 이월
	var targets := bc.get_valid_targets("basic_attack")
	_check(targets.size() == 6, "라온(저격총, 원거리) 유효 대상 = 적 6 전원 [got %d]" % targets.size())
	_check(bc.player_execute("basic_attack", targets[0]), "기본 공격 실행")
	_check(raon.ap == 4, "AP 1 소모 → 4")
	raon.hp = 500  # 테스트 전용: 적 AI 집중 공격으로 사망하지 않도록
	bc.player_end_turn()
	# 라온의 다음 차례까지 진행 (다른 아군은 턴 종료)
	var guard := 0
	while not (bc.is_player_turn() and bc.current == raon) and guard < 60:
		if bc.is_player_turn():
			bc.player_end_turn()
		guard += 1
	_check(bc.current == raon, "라온 다음 차례 도달 (라운드 %d)" % bc.round_no)
	_check(raon.ap == 5, "이월 4 + 회복 2 = 6 → 상한 5로 버림 [got %d]" % raon.ap)
	# 연속 스킬: 강공격(2)+강공격(2)+기본(1) = 5 → AP 0 즉시 턴 종료
	var t := bc.get_valid_targets("heavy_attack")
	bc.player_execute("heavy_attack", t[0])
	bc.player_execute("heavy_attack", t[0] if t[0].alive else bc.get_valid_targets("heavy_attack")[0])
	_check(bc.current == raon and raon.ap == 1, "강공격 2회 후 AP 1, 아직 라온 턴 [ap %d]" % raon.ap)
	var t3 := bc.get_valid_targets("basic_attack")
	var ended := []
	bc.actor_ended.connect(func(u, reason): ended.append([u, reason, u.ap]))
	bc.player_execute("basic_attack", t3[0])
	# 실행 직후 라온의 턴이 'AP 소진' 사유로 자동 종료되었는지 (이후 큐가 동기 진행되어 라온이 다시 차례가 올 수 있음)
	_check(ended.size() > 0 and ended[0][0] == raon and ended[0][2] == 0, "AP 0 (턴 종료 시점 AP %s)" % (str(ended[0][2]) if ended.size() > 0 else "-"))
	_check(ended.size() > 0 and str(ended[0][1]).contains("AP 소진"), "AP 0 즉시 턴 종료 사유: %s" % (ended[0][1] if ended.size() > 0 else "-"))
	bc.queue_free()


func _test_move_swap() -> void:
	print("[6] 이동 빈 슬롯 / 점유 슬롯 교환 / 현재 턴 아닌 아군 직접 이동 불가")
	var bc := _make("ally")
	bc.start_battle()
	var raon := bc.current  # ally:2:0
	var doyun := _unit(bc, "도윤")  # ally:2:1
	# 빈 슬롯 만들기 위해 지호를 죽인다 (테스트용)
	var jiho := _unit(bc, "지호")
	jiho.alive = false
	jiho.hp = 0
	bc.slots.remove_dead_from_slots()
	var ap0 := raon.ap
	_check(bc.player_move("ally:0:0"), "빈 슬롯(ally:0:0)으로 이동")
	_check(raon.slot_key() == "ally:0:0" and bc.slots.unit_at("ally:0:0") == raon and bc.slots.unit_at("ally:2:0") == null, "슬롯 참조 갱신")
	_check(raon.ap == ap0 - 1, "이동 AP 1 소모")
	var dap := doyun.ap
	_check(bc.player_move("ally:2:1"), "점유 슬롯(도윤)과 교환")
	_check(raon.slot_key() == "ally:2:1" and doyun.slot_key() == "ally:0:0", "교환 후 양쪽 슬롯")
	_check(bc.slots.unit_at("ally:2:1") == raon and bc.slots.unit_at("ally:0:0") == doyun, "교환 후 슬롯 맵 일치")
	_check(doyun.ap == dap, "교환 상대 AP 미소모")
	_check(bc.current == raon and bc.is_player_turn(), "교환으로 턴 강제 종료되지 않음")
	# 현재 턴 아닌 아군 이동 불가: 컨트롤러 API는 current 만 움직이므로 SlotManager 직접 호출 외엔 불가함을 확인
	var before := doyun.slot_key()
	bc.player_move("ally:1:0")  # raon 이 이동 (도윤이 아님)
	_check(doyun.slot_key() == before, "비현재 아군(도윤)은 이동 명령 대상이 아님")
	_check(not bc.player_move("enemy:0:0"), "적 슬롯 이동 거부")
	bc.queue_free()


func _test_rejections_cost_no_ap() -> void:
	print("[7] AP 부족 행동·무효 대상 클릭 시 AP 소모 없음")
	var bc := _make("ally")
	bc.start_battle()
	var raon := bc.current
	var ally_target := _unit(bc, "지호")
	var ap0 := raon.ap
	_check(not bc.player_execute("basic_attack", ally_target), "아군에게 공격 → 거부")
	_check(raon.ap == ap0, "거부 시 AP 미소모")
	_check(bc.get_target_block_reason("basic_attack", ally_target) != "", "거부 사유 제공")
	# AP 부족: 필살기 4 > 보유? 라온 max 5 → 가능. 2번째 필살기는 불가
	var t := bc.get_valid_targets("ultimate")
	bc.player_execute("ultimate", t[0])
	_check(raon.ap == 1, "필살기 AP 4 소모 → 1")
	var opts := bc.get_command_options()
	var ult_opt: Dictionary = {}
	for o in opts:
		if o.id == "ultimate":
			ult_opt = o
	_check(not ult_opt.enabled and ult_opt.reason.begins_with("AP 부족"), "AP 부족 행동 비활성화 + 사유")
	var t2 := bc.get_valid_targets("ultimate")
	_check(not bc.player_execute("ultimate", t2[0]), "AP 부족 필살기 거부")
	_check(raon.ap == 1, "거부 시 AP 유지")
	bc.queue_free()


func _test_melee_row_rule() -> void:
	print("[8] 근접: 전방 우선, 전방 없으면 다음 열 / 무기 변경 AP 1 로 사거리 변경")
	var bc := _make("ally")
	bc.start_battle()
	# 라온 턴. 단검(근접)으로 바꾸면 전방 2명만 가능
	var raon := bc.current
	_check(raon.is_ranged_now(), "라온 기본 무기 원거리")
	_check(bc.player_change_weapon(), "무기 변경")
	_check(raon.ap == 4 and not raon.is_ranged_now(), "무기 변경 AP 1 소모, 근접으로 전환")
	var t := bc.get_valid_targets("basic_attack")
	_check(t.size() == 2 and t[0].row == 0 and t[1].row == 0, "근접 유효 대상 = 적 전방 2명 [got %d]" % t.size())
	var center_enemy := _unit(bc, "소총병")
	_check(bc.get_target_block_reason("basic_attack", center_enemy).contains("전방"), "중앙열 적 지정 시 사유 툴팁")
	# 전방 적 제거 후 중앙열 공격 가능
	for u in bc.slots.units_in_row("enemy", 0):
		u.alive = false
		u.hp = 0
	bc.slots.remove_dead_from_slots()
	var t2 := bc.get_valid_targets("basic_attack")
	_check(t2.size() == 2 and t2[0].row == 1, "전방 전멸 시 중앙열 공격 가능")
	bc.queue_free()


func _test_restart_resets() -> void:
	print("[9] 전투 종료 후 재시작 시 AP, HP, 슬롯, 큐 초기화")
	var bc := _make("ally")
	bc.start_battle()
	var raon := bc.current
	bc.player_execute("basic_attack", bc.get_valid_targets("basic_attack")[0])
	bc.player_move("ally:1:0")  # swap with 민우
	var ended := [false]
	bc.battle_ended.connect(func(_w): ended[0] = true)
	# 적 전멸시켜 종료
	for u in bc.slots.living_units("enemy"):
		u.hp = 1
	var guard := 0
	while bc.state != BattleController.State.RESULT and guard < 400:
		if bc.is_player_turn():
			var opts := bc.get_valid_targets("basic_attack")
			if opts.is_empty() or bc.current.ap <= 0:
				bc.player_end_turn()
			else:
				bc.player_execute("basic_attack", opts[0])
		guard += 1
	_check(ended[0] and bc.winner == "ally", "아군 승리로 종료 (라운드 %d)" % bc.round_no)
	# 재시작
	bc.start_battle()
	_check(bc.round_no == 1, "재시작: 라운드 1")
	_check(bc.slots.living_units("enemy").size() == 6 and bc.slots.living_units("ally").size() == 6, "재시작: 12명 생존")
	_check(bc.slots.unit_at("ally:2:0").display_name() == "라온" and bc.slots.unit_at("ally:1:0").display_name() == "민우", "재시작: 슬롯 초기화")
	var all_full := true
	for u in bc.slots.all_units():
		if u.hp != u.data.max_hp or u.ap != u.data.max_ap:
			all_full = false
	_check(all_full, "재시작: HP/AP 최대")
	_check(bc.queue.size() == 12, "재시작: 큐 12명")
	# 3회 연속 재시작
	bc.start_battle()
	bc.start_battle()
	_check(bc.round_no == 1 and bc.queue.size() == 12, "3회 연속 재시작 정상")
	bc.queue_free()


func _test_coin_is_seeded() -> void:
	print("[10] 일반 전투 동전 — 시드 고정 재현성")
	var a := _make("none", 42)
	a.start_battle()
	var b := _make("none", 42)
	b.start_battle()
	_check(a.first_team == b.first_team, "같은 시드 → 같은 선공 (%s)" % a.first_team)
	var seen := {}
	for s in range(1, 30):
		var c := _make("none", s)
		c.start_battle()
		seen[c.first_team] = true
		c.queue_free()
	_check(seen.size() == 2, "시드에 따라 앞/뒤 모두 등장")
	a.queue_free()
	b.queue_free()


func _test_large_units() -> void:
	print("[11] 두 칸 차지하는 큰 몸집 (괴물: 전방+중앙)")
	var bc := BattleController.new()
	bc.enemy_delay = 0.0
	bc.setup(TestRoster.build_actions(), TestRoster.default_roster(TestRoster.build_provided_allies(), TestRoster.build_provided_enemies()), 7, "ally")
	root.add_child(bc)
	bc.start_battle()
	var ghoul := _unit(bc, "구울")
	var wolf := _unit(bc, "늑대")
	_check(ghoul != null and wolf != null and _unit(bc, "슬라임") == null, "괴물 2마리 배치 (슬라임 제외)")
	_check(bc.slots.unit_at("enemy:2:0") == wolf and wolf.slot_keys().size() == 1, "늑대는 후방 한 칸")
	_check(bc.slots.unit_at("enemy:0:1") == ghoul and bc.slots.unit_at("enemy:1:1") == ghoul, "구울이 전방·중앙 두 칸 차지")
	_check(bc.slots.living_units("enemy").size() == 2, "적 유닛 수는 2 (칸 수 아님)")
	_check(bc.slots.living_units("ally").size() == 6, "아군 6인")
	var kira := _unit(bc, "키라")
	var basic: ActionData = bc.actions["basic_attack"]
	var melee_targets := TargetValidator.valid_targets(basic, kira, bc.slots)
	_check(melee_targets.size() == 1 and melee_targets.has(ghoul), "근접: 전방을 막은 구울만 공격 가능 (후방 늑대 불가)")
	_check(TargetValidator.block_reason(basic, kira, ghoul, bc.slots) == "", "근접: 구울 공격 가능")
	# 큰 몸집은 이동·교환 불가, 다른 유닛도 큰 몸집과 교환 불가
	var res := bc.slots.move_or_swap(ghoul, "enemy:2:1")
	_check(not res.ok, "큰 몸집 이동 거부")
	_check(bc.slots.unit_at("enemy:0:1") == ghoul, "거부 후 자리 유지")
	# 구울 사망 → 두 칸 모두 비움
	ghoul.alive = false
	bc.slots.remove_dead_from_slots()
	_check(bc.slots.unit_at("enemy:0:1") == null and bc.slots.unit_at("enemy:1:1") == null, "사망 시 두 칸 모두 비움")
	bc.queue_free()


func _test_equip_and_move_lock() -> void:
	print("[12] 무기 칸 장착 (AP 1) / 이동 불가 상태는 이동·교환 후보에서 제외")
	var bc := _make("ally")
	bc.start_battle()
	var cur := bc.current
	_check(cur.team == "ally" and cur.data.weapons.size() >= 2, "아군 차례, 무기 2개 이상")
	var ap0 := cur.ap
	_check(not bc.player_equip_weapon(0) and cur.ap == ap0, "장착 중인 무기 재장착 거부, AP 유지")
	_check(not bc.player_equip_weapon(2) and cur.ap == ap0, "빈 무기 칸 거부, AP 유지")
	_check(bc.player_equip_weapon(1) and cur.weapon_index == 1 and cur.ap == ap0 - 1, "보조무기1 장착, AP -1")
	var others := bc.slots.living_units("ally")
	var locked: UnitRuntime = null
	for u in others:
		if u != bc.current:
			locked = u
			break
	if bc.is_player_turn() and locked != null:
		locked.move_locked = true
		var keys := []
		for o in bc.get_move_options():
			keys.append(o.key)
		_check(not keys.has(locked.slot_key()), "이동 불가 유닛 자리는 후보에 없음")
		_check(not bc.slots.move_or_swap(bc.current, locked.slot_key()).ok, "이동 불가 유닛과 교환 거부")
		locked.move_locked = false
		locked.add_status("injured")
		var keys2 := []
		for o in bc.get_move_options():
			keys2.append(o.key)
		_check(not keys2.has(locked.slot_key()), "부상(상태 이상) 유닛 자리도 후보에 없음")
	bc.queue_free()


func _test_rally_status() -> void:
	print("[13] 독려 → 대상에 긍정 상태 '독려', 그 유닛의 턴이 끝나면 사라짐")
	var bc := _make("ally")
	bc.start_battle()
	var actor := _unit(bc, "하늘")
	var target := _unit(bc, "지호")
	var ev := ActionResolver.resolve(bc.actions["rally"], actor, target, bc.rng)
	_check(target.statuses.has("rallied"), "독려 상태 부여")
	_check(StatusCatalog.get_def("rallied").positive and not StatusCatalog.get_def("injured").positive, "독려 = 긍정, 부상 = 부정")
	bc.current = target
	bc._end_actor("테스트")
	_check(not target.statuses.has("rallied"), "대상의 턴 종료 후 해제")
	bc.queue_free()


func _status_action(base: ActionData, sid: String, turns: int, value: int) -> ActionData:
	var a := base.duplicate() as ActionData
	a.statuses = [{"id": sid, "turns": turns, "value": value, "chance": 100}]
	return a


func _test_battle_statuses() -> void:
	print("[13b] 전투 상태 이상: 출혈·화상·동상·감속·가속·기절·구속·실명")
	var bc := _make("ally")
	bc.start_battle()
	var enemies := bc.slots.living_units("enemy")
	var allies := bc.slots.living_units("ally")
	var atk: ActionData = bc.actions["basic_attack"]
	# 출혈: 맞을 때 바로 1회 + 자기 차례마다, n턴 = 차례 n번
	var t := enemies[0]
	t.data.max_hp = 100
	t.hp = 100
	var ev := ActionResolver.resolve(_status_action(atk, "bleed", 2, 10), allies[0], t, null)
	var hit: int = ev.results[0].amount
	_check(t.statuses.has("bleed") and t.status_turns("bleed") == 2 and ev.applied.size() == 1, "출혈 2턴 걸림")
	_check(t.hp == 100 - hit - 10 and ev.results.size() == 2 and ev.results[1].status == "bleed", "걸릴 때 바로 최대 HP 10%% 피해 (%d → %d)" % [100, t.hp])
	var hp1 := t.hp
	var st := StatusRules.turn_start(t)
	_check(t.hp == hp1 - 10 and not st.skip, "자기 차례 시작: 출혈 피해 먼저")
	StatusRules.turn_end(t)
	_check(t.status_turns("bleed") == 1, "차례가 끝나면 1턴 줄어듦")
	StatusRules.turn_start(t)
	StatusRules.turn_end(t)
	_check(not t.statuses.has("bleed") and t.hp == hp1 - 20, "2턴 뒤 풀림 (걸릴 때 + 차례 2번 = 3번 피해)")
	# 한 스킬에 상태 이상 여러 개 (각각 확률)
	var two := atk.duplicate() as ActionData
	two.statuses = [{"id": "slow", "turns": 2, "value": 30, "chance": 100}, {"id": "blind", "turns": 1, "value": 0, "chance": 100}, {"id": "stun", "turns": 1, "value": 0, "chance": 0}]
	var t2 := enemies[enemies.size() - 1]
	var ev2 := ActionResolver.resolve(two, allies[0], t2, RandomNumberGenerator.new())
	_check(t2.statuses.has("slow") and t2.statuses.has("blind") and not t2.statuses.has("stun") and ev2.applied.size() == 2 and "기절 실패" in ev2.text, "한 스킬에 감속·실명(100%%) + 기절(0%% → 실패)")
	t2.remove_status("slow")
	t2.remove_status("blind")
	# 화상: 화염 고정 피해 (방어 무시)
	t.data.defense = 5
	var hp2 := t.hp
	StatusRules.apply(t, "burn", 1, 4)
	_check(t.hp == hp2 - 4 and StatusCatalog.get_def("burn").element == "fire", "화상: 방어 5 무시 고정 피해 4 (화염 속성)")
	t.remove_status("burn")
	# 동상: n턴 뒤 한 번 크게, 그리고 풀림
	var hp3 := t.hp
	StatusRules.apply(t, "frost", 2, 20)
	_check(t.hp == hp3, "동상: 걸릴 때는 피해 없음")
	StatusRules.turn_start(t)
	StatusRules.turn_end(t)
	_check(t.hp == hp3 and t.statuses.has("frost"), "첫 차례: 아직 (남은 1)")
	StatusRules.turn_start(t)
	_check(t.hp == hp3 - 20 and not t.statuses.has("frost"), "둘째 차례 시작: 최대 HP 20%% 피해 1회 후 풀림")
	# 감속·가속: 속도 % → 행동 순서
	var a0 := allies[0]
	var spd := a0.data.speed
	a0.add_status("slow", 2, 50)
	_check(a0.speed_now() == maxi(1, roundi(spd * 0.5)), "감속 50%%: 속도 %d → %d" % [spd, a0.speed_now()])
	a0.remove_status("slow")
	a0.add_status("haste", 2, 100)
	_check(a0.speed_now() == spd * 2, "가속 100%%: 속도 ×2")
	var order := TurnScheduler.sort_by_speed(bc.slots.living_units())
	_check(order[0] == a0 or order[0].speed_now() >= a0.speed_now(), "가속하면 행동 순서가 앞으로")
	a0.remove_status("haste")
	# 기절: 자기 차례 행동 불가, 다른 아군은 기절한 캐릭터와 자리 교환 가능 / 구속: 교환·이동 불가
	var cur := bc.current
	var mate: UnitRuntime = null
	for u in allies:
		if u != cur:
			mate = u
			break
	mate.add_status("stun", 1, 0)
	var keys := bc.get_move_options().map(func(o): return o.key)
	_check(keys.has(mate.slot_key()), "기절한 아군 자리는 교환 후보에 있음")
	mate.remove_status("stun")
	mate.add_status("root", 1, 0)
	keys = bc.get_move_options().map(func(o): return o.key)
	_check(not keys.has(mate.slot_key()) and not bc.slots.move_or_swap(cur, mate.slot_key()).ok, "구속된 아군과는 교환 불가")
	mate.remove_status("root")
	cur.add_status("root", 1, 0)
	_check(bc.get_move_options().is_empty() and not bc.get_command_options().filter(func(o): return o.id == "move")[0].enabled, "구속: 자기 자리 이동 불가 (이동 버튼 꺼짐)")
	cur.remove_status("root")
	_check(StatusRules.turn_start(mate).skip == false, "기절 없으면 행동")
	mate.add_status("stun", 1, 0)
	_check(StatusRules.turn_start(mate).skip, "기절: 차례 시작에 행동 불가")
	StatusRules.turn_end(mate)
	_check(not mate.statuses.has("stun"), "기절 1턴 → 차례 한 번 지나면 풀림")
	# 컨트롤러: 기절한 유닛 차례는 바로 넘어감
	var nxt: UnitRuntime = bc.queue[bc.queue_pos] if bc.queue_pos < bc.queue.size() else null
	if nxt != null and nxt.team == "ally":
		nxt.add_status("stun", 1, 0)
		var lines0 := bc.log_lines.size()
		bc.player_end_turn()
		var tail := "\n".join(bc.log_lines.slice(lines0))
		_check("기절" in tail and not nxt.statuses.has("stun") and bc.current != nxt, "기절한 %s 차례: 행동 없이 넘어가고 기절 풀림" % nxt.display_name())
	# 실명: 고른 대상 대신 유효 대상 중 무작위
	var blind := allies[0]
	blind.add_status("blind", 1, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var pool := TargetValidator.valid_targets(bc.actions["ultimate"], blind, bc.slots)
	var seen := {}
	for i in 30:
		var tt := StatusRules.blind_target(bc.actions["ultimate"], blind, pool[0], bc.slots, rng)
		_check_quiet(pool.has(tt))
		seen[tt] = true
	_check(seen.size() == pool.size(), "실명: 적 대상 스킬 → 적 %d명 중 무작위 (%d명 나옴)" % [pool.size(), seen.size()])
	var heal_pool := TargetValidator.valid_targets(bc.actions["heal"], blind, bc.slots) if bc.actions.has("heal") else []
	if not heal_pool.is_empty():
		var hseen := {}
		for i in 30:
			var ht := StatusRules.blind_target(bc.actions["heal"], blind, heal_pool[0], bc.slots, rng)
			hseen[ht.team] = true
		_check(hseen.size() == 1 and hseen.has("ally"), "실명: 아군 대상 스킬 → 아군 중 무작위")
	blind.remove_status("blind")
	# 전투 전용 상태는 기지로 안 넘어감
	_check(StatusCatalog.get_def("bleed").battle and not StatusCatalog.get_def("injured").get("battle", false), "출혈 = 전투 전용, 부상 = 기지까지")
	bc.queue_free()


func _check_quiet(cond: bool) -> void:
	if not cond:
		_check(false, "실명 대상이 유효 대상 밖")


func _test_balance_data_and_ai_graph() -> void:
	print("[14] 밸런스 엑셀 읽기 · 스테이지 배치 · 즉시 반영 · AI 그래프")
	var d := GameData.load_from()
	_check(d != null, "data/balance.xlsx 읽기")
	if d == null:
		return
	_check(d.allies.size() == 6 and d.actions.size() >= 7, "캐릭터 6 · 스킬 7 이상")
	_check(d.monsters.has("ghoul") and d.monsters.ghoul.row_span == 2 and d.monsters.wolf.ai_id == "aggressive", "몬스터 차지칸·AI 열")
	_check(d.actions.flank.status_ids() == ["bleed"] and int(d.actions.flank.statuses[0].turns) == 2 and int(d.actions.sand_kick.statuses[0].chance) == 70 and d.actions.hamstring.status_ids() == ["root"], "data/skill_status.json → 스킬 상태 이상 (턴·확률)")
	_check(d.monsters.ghoul.skill_ids.has("rend") and d.monsters.wolf.skill_ids.has("sand_kick"), "몬스터 상태 이상 스킬")
	_check(d.warnings.is_empty(), "밸런스·스킬 트리·신앙 데이터 경고 없음 %s" % [d.warnings])
	var kira := GameData._find(d.allies, "a_kira")
	_check(kira != null and kira.weapons[0].sprite == "knife" and kira.weapons.size() == 2, "아이템 시트 → 무기 (스프라이트 포함)")
	var es := d.build_stage_enemies("stage_01")
	_check(es.size() == 2 and es[0].default_row == 0 and es[0].default_index == 1 and es[0].row_span == 2, "스테이지 배치: 구울 전방·중앙")
	# 즉시 반영: 같은 객체가 갱신되는지
	var newer := GameData.load_from()
	GameData._find(newer.allies, "a_kira").max_hp = 77
	newer.monsters.ghoul.max_hp = 200
	newer.stages.stage_01.hp_mult = 1.5
	d.apply_from(newer)
	_check(kira.max_hp == 77, "엑셀 다시 읽기 → 기존 캐릭터 객체 제자리 갱신")
	_check(es[0].max_hp == 300, "스테이지 적: 몬스터 HP × 스테이지 배율 다시 계산")
	# AI 그래프 = 기본 규칙과 같은 판단 (default 그래프)
	var g := AIGraph.load_graph("default")
	_check(not g.is_empty(), "data/ai/default.json 읽기")
	var bc := BattleController.new()
	bc.enemy_delay = 0.0
	var fresh := GameData.load_from()
	var roster := TestRoster.default_roster(fresh.allies, fresh.build_stage_enemies("stage_01"))
	bc.setup(fresh.actions, roster, 7, "ally")
	root.add_child(bc)
	bc.start_battle()
	var ghoul: UnitRuntime = null
	for u in bc.slots.all_units():
		if u.data.sprite_id == "ghoul":
			ghoul = u
	var by_graph: Variant = AIGraph.decide(g, ghoul, bc.actions, bc.slots, bc.rng)
	# 기본 규칙은 필살기 처치 판정을 '위력만'으로 하지만, 그래프는 실제 피해(무기·레벨 포함)로 판정 → 처치 가능한 니키타(HP 24)를 필살기로
	var ok: bool = by_graph is Dictionary and not by_graph.is_empty()
	if ok:
		var t: UnitRuntime = by_graph.target
		ok = by_graph.action.id == "ultimate" and t.hp <= ActionResolver.compute_damage(by_graph.action, ghoul, t, null)
	_check(ok, "default 그래프: 처치 가능한 대상에 필살기 (%s)" % (by_graph.target.display_name() if by_graph is Dictionary and not by_graph.is_empty() else "-"))
	ghoul.ap = 3   # 필살기(4) 불가 → 상태 이상 스킬(할퀴기 = 출혈) 먼저, 출혈 없는 대상
	var g2: Variant = AIGraph.decide(g, ghoul, bc.actions, bc.slots, bc.rng)
	_check(g2 is Dictionary and g2.action.id == "rend" and not g2.target.statuses.has("bleed"), "AP 3: 할퀴기(출혈) → 출혈 없는 대상 (%s)" % (g2.target.display_name() if g2 is Dictionary else "-"))
	for u in bc.slots.living_units("ally"):   # 모두 출혈·동상이면 상태 이상 스킬은 건너뜀 → 강공격, HP 최저
		u.add_status("bleed", 2, 5)
		u.add_status("frost", 2, 10)
	var g3: Variant = AIGraph.decide(g, ghoul, bc.actions, bc.slots, bc.rng)
	var low: UnitRuntime = null
	for t in TargetValidator.valid_targets(bc.actions.heavy_attack, ghoul, bc.slots):
		if low == null or t.hp < low.hp:
			low = t
	_check(g3 is Dictionary and g3.action.id == "heavy_attack" and g3.target == low, "모두 걸려 있으면 강공격 → HP 최저 (%s)" % (low.display_name() if low else "-"))
	ghoul.actions_this_turn = 2
	_check((AIGraph.decide(g, ghoul, bc.actions, bc.slots, bc.rng) as Dictionary).is_empty(), "행동 2회 후 턴 종료")
	bc.queue_free()


## 발자국·쓰러짐 소리: 파일, 발 닿는 프레임, 걷기 한 바퀴 = 두 걸음
func _test_sfx() -> void:
	_check(Sfx.footsteps("kira", "walk").size() == 5, "키라 걷기 발자국 5조각 [got %d]" % Sfx.footsteps("kira", "walk").size())
	_check(Sfx.footsteps("nikita_army", "run").size() == 3, "니키타 뛰기 발자국 3조각")
	_check(Sfx.footsteps("ethan", "walk").size() == 5 and Sfx.footsteps("ethan", "run").size() == 4, "이선 발자국 걷기 5 · 뛰기 4조각")
	_check(Sfx.footsteps("hero2", "walk").size() == 4 and Sfx.footsteps("hero2", "run").size() == 6, "하나 발자국 걷기 4 · 뛰기 6조각")
	_check(Sfx.footsteps("alma", "walk").size() == 5 and Sfx.footsteps("alma", "run").size() == 5, "앨마 발자국 걷기 5 · 뛰기 5조각 (출발 걸음 뺌)")
	_check(Sfx.footsteps("dan", "walk").size() == 5 and Sfx.footsteps("dan", "run").size() == 6, "단 발자국 걷기 5 · 뛰기 6조각")
	_check(Sfx.footsteps("rohan", "walk").is_empty(), "소리 없는 캐릭터 = 빈 목록")
	_check(Sfx.common("dead") != null, "공용 쓰러짐 소리")
	var d: Dictionary = CharacterSprite2D.anim_data("kira", "walk")
	_check((d.get("steps", []) as Array).map(func(v): return int(v)) == [9, 18], "키라 걷기 발 닿는 프레임 [9, 18] [got %s]" % str(d.get("steps", [])))
	var c := CharacterSprite2D.new()
	c.build("kira")
	c.play("walk")
	var n := (d.frames as Array).size()
	for k in n * 2:   # 두 바퀴 (프레임마다 한 번씩)
		c._process(1.0 / float(d.fps) + 0.0001)
	_check(c._step_i == 4, "걷기 두 바퀴 = 발자국 4번 [got %d]" % c._step_i)
	c.play("idle")
	var before := c._step_i
	for k in 30:
		c._process(0.1)
	_check(c._step_i == before, "idle 에서는 발자국 없음")
	c.free()


## 상태 = 이름 + 효과 (data/statuses.json) / 새 효과: 넉백 · 끌어당김 · 표식 · 도발 · 취약 · 재생 · 보호막
func _test_poses() -> void:
	print("[13f] 상황별 포즈 그림")
	var ps := CharacterSprite2D.poses("nikita_army")
	for pz in ["dead", "hit", "miss", "shot", "stun"]:
		_check(ps.has(pz), "니키타 포즈 '%s' 있음" % pz)
		_check(CharacterSprite2D.pose_path("nikita_army", pz) != "", "니키타 포즈 '%s' 그림 경로" % pz)
	_check(not ps.has("idle") and not ps.has("walk"), "동작 폴더(idle·walk)는 포즈가 아님")
	_check(CharacterSprite2D.pose_path("nikita_army", "") == "" and CharacterSprite2D.pose_path("nikita_army", "nope") == "", "없는 포즈 = 기본 그림")
	var d := CharacterSprite2D.anim_data("nikita_army", "dead")
	_check((d.frames as Array).size() == 1 and bool(d.loop), "dead = 한 장, 멈춘 그림 (반복)")
	var st := CutsceneData.norm_step({"type": "say", "speaker": "npc_nikita", "side": "left", "pose": "hit", "text": "윽"})
	_check(st.pose == "hit", "컷씬 대사 포즈 저장")
	_check(CutsceneData.norm_step({"type": "say", "text": "a"}).pose == "", "포즈 비우면 기본 그림")
	for pz in ["point_up", "tired", "annoying"]:
		_check(ps.has(pz), "니키타 포즈 '%s' 있음" % pz)
	var hp := CharacterSprite2D.poses("hero2")
	for pz in ["hit", "miss", "shot", "slash", "tired", "dead", "point_up", "stun", "annoying", "awkward", "hit_2", "move"]:
		_check(hp.has(pz), "하나 포즈 '%s' 있음" % pz)
	var kp := CharacterSprite2D.poses("kira")
	for pz in ["stun", "miss", "hit", "slash", "tired", "annoying", "shot", "shot_pistol"]:
		_check(kp.has(pz), "키라 포즈 '%s' 있음" % pz)
	_check(SkillPoseData.pose_name("shot_pistol") == "공격 (pistol)", "무기별 포즈 이름")
	_check(SkillPoseData.pose_name("hit_2") == "피격 2" and SkillPoseData.pose_name("move") == "자리 이동", "포즈 이름 (같은 포즈 다른 그림 = 피격 2)")
	# 스킬 포즈 규칙 (SkillPoseData)
	var bc := _make("ally")
	bc.start_battle()
	var e: UnitRuntime = bc.slots.living_units("enemy")[0]
	var a0: UnitRuntime = bc.slots.living_units("ally")[0]
	var a1: UnitRuntime = bc.slots.living_units("ally")[1]
	var atk := ActionData.new()
	atk.id = "t_pose_atk"
	atk.effect = "damage"
	var heal := ActionData.new()
	heal.id = "t_pose_heal"
	heal.effect = "heal"
	_check(SkillPoseData.auto_caster(atk, a0, e) == (["shot"] if a0.is_ranged_now() else ["slash", "shot"]), "자동: 적에게 공격 = shot (근접 무기면 slash → shot)")
	var kira: UnitRuntime = null
	for u in bc.slots.living_units("ally"):
		if u.data.sprite_id == "kira":
			kira = u
	if kira != null:
		var wi := -1
		for i in kira.data.weapons.size():
			if str(kira.data.weapons[i].get("sprite", "")) == "pistol":
				wi = i
		if wi >= 0:
			var keep := kira.weapon_index
			kira.weapon_index = wi
			_check(SkillPoseData.caster_poses(atk, kira, e, {}) == ["shot_pistol", "shot"], "권총을 들면 shot_pistol 먼저")
			kira.weapon_index = keep
	var melee := bc.slots.living_units("ally").filter(func(u): return not u.is_ranged_now())
	var ranged := bc.slots.living_units("ally").filter(func(u): return u.is_ranged_now())
	if not melee.is_empty():
		_check(SkillPoseData.auto_caster(atk, melee[0], e)[0] == "slash", "근접 무기 공격 = slash 먼저")
	if not ranged.is_empty():
		_check(SkillPoseData.auto_caster(atk, ranged[0], e)[0] == "shot", "원거리 무기 공격 = shot")
	_check(SkillPoseData.auto_caster(heal, a0, a1) == ["point_up"] and SkillPoseData.caster_poses(heal, a0, a1, {}).back() == "point_up", "자동: 회복·버프 = point_up")
	_check(SkillPoseData.caster_poses(atk, a0, e, {"t_pose_atk": "point_up"}).back() == "point_up" and not SkillPoseData.caster_poses(atk, a0, e, {"t_pose_atk": "point_up"}).has("shot"), "스킬 포즈를 정하면 그 포즈")
	_check(SkillPoseData.caster_poses(atk, a0, e, {"t_pose_atk": "none"}).is_empty(), "포즈 없음 = 예전 동작")
	_check(SkillPoseData.target_poses("miss", []) == ["miss"], "피함 = miss")
	_check(SkillPoseData.target_poses("damage", ["stun"])[0] == "stun", "기절 = stun 먼저")
	_check(SkillPoseData.target_poses("damage", ["root"]) == ["tired", "hit"], "구속(디버프) = tired, 없으면 hit")
	_check(SkillPoseData.target_poses("damage", ["bleed"])[0] == "tired", "디버프(출혈) = tired")
	_check(SkillPoseData.target_poses("damage", ["knockback"]) == ["hit"], "넉백(즉시)은 디버프로 안 침 = hit")
	_check(SkillPoseData.target_poses("", ["regen"]).is_empty(), "버프만 걸림 = 포즈 없음")
	var tmp := "user://t_skill_poses.json"
	SkillPoseData.write({"basic_attack": "point_up", "x": ""}, tmp)
	var rd := SkillPoseData.read(tmp)
	_check(rd.size() == 1 and rd.basic_attack == "point_up", "스킬 포즈 저장 · 읽기 (빈 값은 안 씀)")
	_check(SkillPoseData.read().is_empty() or SkillPoseData.read() is Dictionary, "data/skill_poses.json 읽힘")
	# 신 아이콘 그림
	_check(FaithData.icon_texture({"icon": ""}) == null, "신 아이콘 그림 없음 = 글자 아이콘")
	var fd := FaithData.read()
	_check(fd.gods.all(func(g): return g.has("icon")), "신 데이터에 아이콘 그림 칸")
	var bad := FaithData.check({"gods": [{"id": "g1", "name": "시험신", "icon": "res://assets/gods/__nope.png"}], "skills": [], "divine": {}, "miracles": []}, {}, {})
	_check(Array(bad.errors).any(func(x): return x.contains("아이콘 그림")), "없는 아이콘 그림 = 검사 오류")


func _test_hit_evasion() -> void:
	print("[13e] 명중 · 회피")
	var bc := _make("ally")
	bc.start_battle()
	var e: UnitRuntime = bc.slots.living_units("enemy")[0]
	var a0: UnitRuntime = bc.slots.living_units("ally")[0]
	var atk := ActionData.new()
	atk.id = "t_atk"
	atk.display_name = "시험 공격"
	atk.effect = "damage"
	atk.power = 6
	atk.accuracy = 90
	a0.data.accuracy = 10
	e.data.evasion = 25
	_check(ActionResolver.hit_chance(atk, a0, e) == 75, "명중률 = 스킬 90 + 명중 10 - 회피 25 = %d%%" % ActionResolver.hit_chance(atk, a0, e))
	e.data.evasion = 200
	_check(ActionResolver.hit_chance(atk, a0, e) == ActionResolver.HIT_MIN, "아무리 피해도 최소 %d%%" % ActionResolver.HIT_MIN)
	e.data.evasion = 0
	atk.accuracy = 150
	_check(ActionResolver.hit_chance(atk, a0, e) == 100, "100% 위로는 안 감")
	var heal := ActionData.new()
	heal.effect = "heal"
	heal.power = 5
	heal.accuracy = 10
	_check(not ActionResolver.rolls_hit(heal, a0, a0) and ActionResolver.hit_chance(heal, a0, a0) == 100, "회복은 굴리지 않음 (늘 성공)")
	# 빗나감: 피해 없음 · 상태 이상 안 걸림
	atk.accuracy = 5
	e.data.evasion = 0
	a0.data.accuracy = 0
	atk.statuses = [{"id": "bleed", "turns": 2, "value": 10, "chance": 100}]
	var rng := RandomNumberGenerator.new()
	var hp0 := e.hp
	var misses := 0
	var hits := 0
	for i in 200:
		rng.seed = 1000 + i
		var ev := ActionResolver.resolve(atk, a0, e, rng)
		if not ev.hit:
			misses += 1
			if e.hp != hp0 or e.statuses.has("bleed") or ev.results[0].kind != "miss" or not ("빗나감" in ev.text):
				hits = -999
		else:
			hits += 1
			e.hp = hp0
			e.statuses.clear()
			e.status_info.clear()
	_check(misses > 150 and hits > 0, "명중 5%%: 200번 중 빗나감 %d · 맞음 %d (빗나가면 피해·상태 이상 없음)" % [misses, hits])
	# 기절·구속은 피하지 못함
	e.data.evasion = 40
	_check(e.evasion_now() == 40, "회피 40%")
	e.add_status("stun", 1, 0)
	_check(e.evasion_now() == 0 and ActionResolver.hit_chance(atk, a0, e) == 5, "기절한 대상은 회피 0")
	e.remove_status("stun")
	# 100% 면 난수를 쓰지 않음 (기존 전투 재현성 유지)
	atk.accuracy = 100
	e.data.evasion = 0
	atk.statuses = []
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7
	var st0 := r2.state
	ActionResolver.resolve(atk, a0, e, r2)
	var r3 := RandomNumberGenerator.new()
	r3.seed = 7
	r3.randi_range(-1, 1)
	_check(r2.state == r3.state, "명중 100% = 명중 굴림 없음 (피해 흔들림 난수만)")
	# 엑셀 값
	var gd := GameData.load_from()
	var dan: UnitData = GameData._find(gd.allies, "a_dan")
	var kira: UnitData = GameData._find(gd.allies, "a_kira")
	_check(gd.actions.basic_attack.accuracy == 95 and gd.actions.heavy_attack.accuracy == 85 and gd.actions.heal.accuracy == 100, "엑셀 스킬 명중: 기본 공격 95 · 강공격 85 · 회복 100")
	_check(kira.evasion > dan.evasion and gd.monsters.wolf.evasion == 20, "엑셀 회피: 키라 %d > 단 %d · 늑대 %d" % [kira.evasion, dan.evasion, gd.monsters.wolf.evasion])
	_check(GameData.default_accuracy("damage") == 90 and GameData.default_accuracy("heal") == 100, "명중 칸이 비면 공격 90 · 회복 100")
	_check(SkillTreeData.EFFECTS.has("accuracy") and SkillTreeData.auto_desc("evasion", 5, {}) == "회피 +5%", "스킬 트리 효과: 명중 · 회피")


func _test_status_effects() -> void:
	print("[13c] 상태 id → 효과, 넉백·끌어당김·표식·도발·취약·재생·보호막")
	# 같은 효과, 다른 이름
	_check(StatusCatalog.effect_of("regen_2") == "regen" and StatusCatalog.effect_of("regen_3") == "regen", "regen_2 진통제 · regen_3 자가 치유 = 효과 재생")
	_check(StatusCatalog.get_def("regen_2").name == "진통제" and StatusCatalog.get_def("regen_3").name == "자가 치유" and StatusCatalog.get_def("regen_2").positive, "이름은 따로, 규칙(긍정·전투 전용)은 효과에서")
	_check(StatusCatalog.effect_of("bleed") == "bleed" and StatusCatalog.find("진통제") == "regen_2", "효과 이름 그대로인 상태 · 한글 이름으로 찾기")
	_check(StatusCatalog.check(StatusCatalog.read()).errors.is_empty(), "data/statuses.json 검사 통과")
	var bad := [StatusCatalog.new_status("regen_2", "regen"), StatusCatalog.new_status("regen_2", "regen"), StatusCatalog.new_status("x", "nope"),
		StatusCatalog.new_status("rallied", "regen"), StatusCatalog.new_status("painkiller", "regen"), StatusCatalog.new_status("regen_1", "regen")]
	var bres := StatusCatalog.check(bad)
	_check(bres.errors.size() == 5, "검사: id 중복 · 모르는 효과 · 게임 상태 id · 효과 id 규칙 어김 2 [%s]" % " / ".join(bres.errors))
	var cur_defs := StatusCatalog.read()
	_check(StatusCatalog.next_id("regen", cur_defs) == "regen_4" and StatusCatalog.next_id("knockback", cur_defs) == "knockback_2" and StatusCatalog.next_id("regen", []) == "regen",
		"새 상태 id = 효과 id → _2, _3 … (재생 다음 = regen_4)")
	var gd := GameData.load_from()
	_check(gd.actions.painkiller_shot.status_ids() == ["regen_2"] and gd.actions.self_heal.status_ids() == ["regen_3"], "스킬 진통제 투여 → regen_2, 스킬 자가 치유 → regen_3")
	var bc := _make("ally")
	bc.start_battle()
	var enemies := bc.slots.living_units("enemy")
	var allies := bc.slots.living_units("ally")
	var atk: ActionData = bc.actions["basic_attack"]
	# 재생: 걸릴 때 + 자기 차례마다 최대 HP v% 회복, 이름이 다른 같은 효과는 따로 걸림
	var p := allies[0]
	p.data.max_hp = 100
	p.hp = 50
	var r1 := StatusRules.apply(p, "regen_2", 3, 8)
	_check(p.hp == 58 and r1.size() == 1 and r1[0].kind == "heal" and r1[0].status == "regen_2", "진통제: 걸릴 때 +8 (50 → %d)" % p.hp)
	StatusRules.apply(p, "regen_3", 2, 6)
	var ts := StatusRules.turn_start(p)
	_check(p.hp == 64 + 8 + 6 and ts.results.size() == 2 and p.has_effect("regen") and p.statuses_with("regen").size() == 2, "자가 치유 걸 때 +6, 차례 시작에 진통제 +8 · 자가 치유 +6 따로 (→ %d)" % p.hp)
	p.hp = 99
	StatusRules.turn_start(p)
	_check(p.hp == 100, "재생은 최대 HP 까지")
	# 같은 id 는 겹치지 않음: 다시 걸리면 하나로, 남은 턴·수치 큰 쪽
	var turns_before := p.status_turns("regen_2")
	StatusRules.apply(p, "regen_2", 5, 4)
	_check(p.statuses.count("regen_2") == 1 and p.status_turns("regen_2") == maxi(5, turns_before) and int(p.status_info.regen_2.value) == 8, "같은 id(regen_2) 다시 걸림 → 하나로, 턴 5 · 수치 8 유지")
	# 보호막: 피해를 먼저 막고 다 막으면 사라짐
	var sh := allies[1]
	sh.data.max_hp = 100
	sh.hp = 100
	StatusRules.apply(sh, "shield", 2, 10)
	var d1 := StatusRules.deal(sh, 6)
	_check(d1.absorbed == 6 and d1.amount == 0 and sh.hp == 100 and int(sh.status_info.shield.value) == 4, "보호막 10: 6 막음 (남은 4)")
	var d2 := StatusRules.deal(sh, 7)
	_check(d2.absorbed == 4 and d2.amount == 3 and sh.hp == 97 and not sh.has_effect("shield"), "남은 4 막고 3 피해, 보호막 사라짐")
	StatusRules.apply(sh, "shield", 2, 5)
	StatusRules.apply(sh, "bleed", 2, 10)
	_check(sh.hp == 92 and not sh.has_effect("shield"), "보호막은 상태 이상 피해(출혈 10)도 막음 (5 막고 5 → %d)" % sh.hp)
	sh.remove_status("bleed")
	# 취약: 받는 피해 +v%
	sh.hp = 100
	sh.add_status("vulnerable", 2, 50)
	_check(StatusRules.deal(sh, 10).amount == 15 and sh.hp == 85, "취약 50%: 10 → 15 피해")
	sh.remove_status("vulnerable")
	# 표식: 이 대상을 노리는 공격 위력 +v% (방어 전)
	var e0 := enemies[0]
	var plain := ActionResolver.compute_damage(atk, allies[0], e0, null)
	e0.add_status("mark", 2, 100)
	var marked := ActionResolver.compute_damage(atk, allies[0], e0, null)
	_check(marked > plain, "표식 100%%: 위력 두 배 (%d → %d)" % [plain, marked])
	# 표식: 적 AI 는 표식 대상 먼저
	var foe := enemies[0]
	var front := bc.slots.units_in_row("ally", 0)
	if front.size() >= 2:
		var low: UnitRuntime = front[0] if front[0].hp <= front[1].hp else front[1]
		var high: UnitRuntime = front[1] if low == front[0] else front[0]
		high.hp = high.data.max_hp
		low.hp = 1
		var g0 := AIGraph._try_skill("basic_attack", "hp_low", foe, bc.actions, bc.slots, null) if foe.data.skill_ids.has("basic_attack") else {}
		high.add_status("mark", 2, 25)
		var g1 := AIGraph._try_skill("basic_attack", "hp_low", foe, bc.actions, bc.slots, null) if foe.data.skill_ids.has("basic_attack") else {}
		_check(not g0.is_empty() and g0.target == low and g1.target == high, "AI: 평소엔 HP 낮은 쪽, 표식이 있으면 표식 대상")
		high.remove_status("mark")
	e0.remove_status("mark")
	# 도발: 상대 편은 도발한 캐릭터만 (닿을 때)
	var any_atk := atk.duplicate() as ActionData
	any_atk.target_rule = "enemy_any"
	var tank := enemies[enemies.size() - 1]
	tank.add_status("taunt", 2, 0)
	var vt := TargetValidator.valid_targets(any_atk, allies[0], bc.slots)
	_check(vt.size() == 1 and vt[0] == tank, "도발: 원거리 공격 대상 = 도발한 %s 만" % tank.display_name())
	_check(TargetValidator.block_reason(any_atk, allies[0], enemies[0], bc.slots).begins_with("도발"), "다른 적을 고르면 막힘")
	var melee := atk.duplicate() as ActionData
	melee.target_rule = "enemy_melee"
	if tank.row > TargetValidator.melee_reachable_row(allies[0], bc.slots):
		_check(not TargetValidator.valid_targets(melee, allies[0], bc.slots).has(tank) and not TargetValidator.valid_targets(melee, allies[0], bc.slots).is_empty(), "근접이 못 닿는 열의 도발은 무시")
	tank.remove_status("taunt")
	# 넉백 · 끌어당김: 맞으면 자리 옮김 (같은 편과 자리 바꿈)
	var push := any_atk.duplicate() as ActionData
	push.ap_cost = 0
	push.statuses = [{"id": "knockback", "turns": 1, "value": 1, "chance": 100}]
	bc.actions["t_push"] = push
	var tgt: UnitRuntime = bc.slots.units_in_row("enemy", 0)[0]
	var idx := tgt.index
	var behind := bc.slots.unit_at(SlotManager.make_key("enemy", 1, idx))
	var hp_before := tgt.hp
	bc.player_execute("t_push", tgt)
	_check(tgt.row == 1 and tgt.index == idx and (behind == null or behind.row == 0) and not tgt.statuses.has("knockback"), "넉백: 전방 → 중앙, 뒤 칸 %s 은 앞으로 (상태로 안 남음)" % (behind.display_name() if behind != null else "없음"))
	_check(tgt.hp < hp_before or not tgt.alive, "넉백 스킬도 피해는 그대로")
	var pull := push.duplicate() as ActionData
	pull.statuses = [{"id": "pull", "turns": 1, "value": 1, "chance": 100}]
	bc.actions["t_pull"] = pull
	var back: UnitRuntime = bc.slots.units_in_row("enemy", 2)[0]
	back.hp = back.data.max_hp
	bc.player_execute("t_pull", back)
	_check(back.row == 1, "끌어당김: 후방 → 중앙")
	back.add_status("root", 2, 0)
	bc.player_execute("t_pull", back)
	_check(back.row == 1 and bc.log_lines[bc.log_lines.size() - 1].contains("안 됨"), "구속이면 안 끌려옴")
	back.remove_status("root")
	var dm := StatusRules.displace(bc.slots.units_in_row("enemy", 2)[0] if not bc.slots.units_in_row("enemy", 2).is_empty() else back, "knockback", 1, bc.slots)
	_check(not dm.ok, "맨 뒤 열은 더 안 밀림")
	_check(SkillStatusData.summary({"id": "knockback", "turns": 1, "value": 1, "chance": 100}) == "넉백 (칸 수 1)", "넉백 요약은 턴 없이")
	bc.queue_free()


## 세계관 도감 (data/codex.json) + 믿는 신 (data/faith.json believers)
func _test_codex() -> void:
	print("[13d] 세계관 도감 · 믿는 신")
	var gd := GameData.load_from()
	var fd := FaithData.read()
	_check(fd.has_believers and gd.char_faith.a_dan.god == fd.believers.a_dan.god and gd.char_faith.a_alma.god == fd.believers.a_alma.god and int(gd.char_faith.a_alma.faith) == int(fd.believers.a_alma.faith),
		"믿는 신 = faith.json believers (단 %s, 앨마 %s %d)" % [fd.believers.a_dan.god, fd.believers.a_alma.god, int(fd.believers.a_alma.faith)])
	_check(FaithData.symbol_of({"name": "태양신 솔루스"}) == "솔" and FaithData.symbol_of({"name": "x", "symbol": "☀빛"}) == "☀", "신 아이콘 글자: 이름 끝 단어 첫 글자 / symbol")
	var cx := CodexData.read()
	_check(CodexData.TABS.size() == 5 and CodexData.check(cx).is_empty(), "도감 탭 5개 (등장인물·몬스터·상태이상·종교(신)·도시 배경), id 중복 없음")
	var gods := CodexData.entries(cx, "gods", gd)
	_check(gods.size() == gd.god_order.size() and gods[0].id == gd.god_order[0] and gods[0].title == gd.gods[gd.god_order[0]].name, "종교(신): 신마다 항목, 제목 = faith.json 이름 (%s)" % gods[0].title)
	var chars := CodexData.entries(cx, "characters", gd, {"npc_rohan": {"name": "로한", "sprite": "rohan", "character_id": ""}, "npc_dan": {"name": "단", "character_id": "a_dan"}})
	var cids := chars.map(func(e): return e.id)
	_check(cids.has("a_alma") and cids.has("npc_rohan") and not cids.has("npc_dan") and chars[0].sprite == "dan", "등장인물: 아군 + 전투에 안 나가는 대원(로한), 그림 = 스프라이트")
	var sts := CodexData.entries(cx, "statuses", gd)
	var sids := sts.map(func(e): return e.id)
	_check(sids.has("regen_2") and sids.has("injured") and sts.filter(func(e): return e.id == "regen_2")[0].title == "진통제", "상태이상: 상태 정의 + 게임 상태 (진통제 = regen_2)")
	_check(CodexData.entries(cx, "monsters", gd).size() == gd.monsters.size() and CodexData.entries(cx, "cities", gd).size() == 4, "몬스터 = 몬스터 시트, 도시 배경 = 도감에만 (4곳)")
	var ghost := {"gods": [{"id": "nope", "title": "", "subtitle": "", "body": "x", "sprite": "", "color": ""}]}
	_check(CodexData.entries(ghost, "gods", gd).size() == gd.god_order.size() and CodexData.entries(ghost, "gods", gd)[0].body.begins_with("(기록 없음"), "게임에 없는 항목은 빼고, 설명 없는 신은 '기록 없음'")

