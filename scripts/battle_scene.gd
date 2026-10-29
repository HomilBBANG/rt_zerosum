extends Node
## 전투 씬 스크립트 (battle_2d.tscn).
## 컨트롤러 생성 → 뷰/HUD 연결 → 전투 시작 → 결과 전환. 단축키: 1~4 조명 프리셋, L 전투 기록, F1 디버그, F2 HUD, F3 림 라인, R 재시작, Esc 메뉴.

@onready var view: BattleViewBase = $View
@onready var hud: BattleHUD = $HUD

var controller: BattleController
var preset: Dictionary


func _ready() -> void:
	controller = BattleController.new()
	controller.name = "BattleController"
	add_child(controller)
	controller.setup(Game.actions, Game.build_roster(), Game.seed_value, Game.ambush)
	if Game.cli.has("enemy_delay"):
		controller.enemy_delay = float(Game.cli.enemy_delay)
	preset = LightingPresets.get_preset(Game.preset)
	view.setup(controller, preset)
	hud.setup(controller, view, preset)
	controller.battle_ended.connect(_on_battle_ended)
	Game.data_reloaded.connect(_on_data_reloaded)
	if Game.cli.get("hud", "1") == "0":
		hud.visible = false
	# 일반 전투(동전)는 선공 동전 연출이 끝난 뒤 첫 라운드 시작. 스크린샷 자동화는 --coin=1 일 때만 연출
	controller.wait_for_intro = Game.ambush == "none" and Game.cli.get("coin", "0" if Game.cli.has("shot") else "1") == "1"
	controller.initiative_decided.connect(_on_initiative)
	if Game.cli.has("try_skill") and Game.actions.has(str(Game.cli.try_skill)):   # 에디터 '상태 이상' 테스트: 아군 모두 첫 스킬 칸에
		for e in controller._roster:
			var ud: UnitData = e.data
			if ud.team == "ally" and not ud.skill_ids.has(str(Game.cli.try_skill)):
				ud.skill_ids.insert(0, str(Game.cli.try_skill))
	controller.start_battle()
	if Game.cli.get("status_demo", "0") == "1":   # 스크린샷용: 첫 아군에 상태 이상 예시
		for u in controller.slots.living_units("ally"):
			u.add_status("rallied")
			u.add_status("injured")
		hud._refresh_panel()
	if Game.cli.has("battle_status"):   # 스크린샷·확인용: --battle_status=a_dan:bleed:2:10;wolf:stun:1:0 (캐릭터 id 또는 스프라이트:상태:턴:수치)
		for spec in str(Game.cli.battle_status).split(";", false):
			var p := spec.split(":")
			for u in controller.slots.living_units():
				if p.size() >= 2 and (u.data.id == p[0] or u.data.sprite_id == p[0]):
					u.add_status(StatusCatalog.find(p[1]), int(p[2]) if p.size() > 2 else 2, int(p[3]) if p.size() > 3 else 10)
		hud._refresh_panel()
	if Game.cli.has("anim_frame"):   # 확인용: --anim_frame=a_alma:death:19;a_dan:attack:5 (캐릭터 id 또는 스프라이트:동작:프레임 0부터) — 그 프레임에 멈춤
		for spec in str(Game.cli.anim_frame).split(";", false):
			var p := spec.split(":")
			for u in controller.slots.all_units():
				var sp = view.sprite_of(u) if view.has_method("sprite_of") else null
				if p.size() >= 3 and (u.data.id == p[0] or u.data.sprite_id == p[0]) and sp != null and sp.chr != null:
					sp.chr.freeze(p[1], int(p[2]))
	_run_cli()


func _on_initiative(_first: String, _reason: String) -> void:
	if not controller.wait_for_intro:
		return
	if controller.coin_face == "":
		controller.begin_rounds.call_deferred()
		return
	var coin := CoinFlip.new()
	add_child(coin)
	coin.finished.connect(controller.begin_rounds)
	coin.play(controller.coin_face, "아군 선공" if controller.first_team == "ally" else "적 선공")


## 밸런스 엑셀이 저장되면 진행 중인 전투에도 바로 반영 (최대 HP·AP 가 줄면 현재 값도 맞춤)
func _on_data_reloaded(warnings: PackedStringArray) -> void:
	for u in controller.slots.all_units():
		u.hp = mini(u.hp, u.data.max_hp)
		u.ap = mini(u.ap, u.data.max_ap)
	hud._refresh_panel()
	hud._refresh_floating()
	hud._refresh_timeline()
	hud.show_toast("밸런스 데이터 적용 (balance.xlsx)" + ("" if warnings.is_empty() else "  ⚠ " + warnings[0]))


func _on_battle_ended(winner: String) -> void:
	await get_tree().create_timer(1.4).timeout
	if Game.cli.has("shot"):
		return
	var allies := []
	for u in controller.slots.all_units():
		if u.team == "ally":
			allies.append({"id": u.data.id, "hp": u.hp, "alive": u.alive, "statuses": u.statuses.duplicate()})
	Game.show_result({"winner": winner, "rounds": controller.round_no, "log": controller.log_lines.duplicate(), "mode": Game.mode,
		"allies": allies, "stage": Game.stage_id})


func set_preset(id: String) -> void:
	Game.preset = id
	preset = LightingPresets.get_preset(id)
	view.apply_preset(preset)
	hud.apply_preset(preset)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1: set_preset("g1")
			KEY_2: set_preset("g2")
			KEY_3: set_preset("g3")
			KEY_4: set_preset("g4")
			KEY_F1: hud.toggle_debug()
			KEY_L: hud.toggle_log()
			KEY_F3:
				Game.rim_enabled = not Game.rim_enabled
				view.apply_preset(preset)
				hud.show_toast("림 라인 %s" % ("켬" if Game.rim_enabled else "끔"))
			KEY_F2: hud.visible = not hud.visible
			KEY_R:
				Game.restart_count += 1
				Game.start_battle()
			KEY_ESCAPE: Game.go_menu()


## CLI 자동 진행 (스크린샷/검증용): --autoplay=aim|move|fight:N|slot:i:press|hover|pose:<포즈>[:초]
func _run_cli() -> void:
	var auto: String = Game.cli.get("autoplay", "")
	if auto != "":
		await get_tree().create_timer(0.3).timeout
		var steps := 0
		var max_steps := 6
		if auto.begins_with("fight"):
			max_steps = int(auto.get_slice(":", 1)) if auto.contains(":") else 6
		var guard := 0
		while guard < 200 and controller.state != BattleController.State.RESULT:
			guard += 1
			if not controller.is_player_turn() or view.busy:
				await get_tree().process_frame
				continue
			if auto == "aim":
				hud.begin_action("heavy_attack" if controller.current.ap >= 2 else "basic_attack")
				break
			if auto == "move":
				hud.begin_move()
				break
			if auto.begins_with("pose"):
				# --autoplay=pose:<shot|hit|miss|stun|dead…>[:초] — 포즈 그림이 있는 첫 아군(--pose_char=스프라이트 id 로 고르기)에게 그 연출, 초 뒤에 찍음 (기본 0.6)
				var pz := auto.get_slice(":", 1)
				for id in view.sprites:
					var sp: UnitSprite2D = view.sprites[id]
					if sp.has_pose(pz) and Game.cli.get("pose_char", sp.unit.data.sprite_id) == sp.unit.data.sprite_id:
						if pz == "dead":
							sp.play_death()
						else:
							var po: Dictionary = view.pose_opts()
							if Game.cli.has("pose_zoom"):   # --pose_zoom=1 = 줌 없이 (크기 확인)
								po.zoom = float(Game.cli.pose_zoom)
								po.drift = 0.0
							sp.play_pose(pz, po)
							view.focus_camera(sp, po)
							if pz in ["shot", "hit"]:
								view.shake_camera()
						break
				await get_tree().create_timer(float(auto.get_slice(":", 2)) if auto.get_slice_count(":") > 2 else 0.6).timeout
				break
			if auto.begins_with("slot"):
				# --autoplay=slot:<번호>:press|hover — 하단 슬롯 클릭/호버 (0~2 무기, 3 이동, 4~6 스킬, 7 필살기)
				await get_tree().process_frame
				var b := hud.debug_slot_button(int(auto.get_slice(":", 1)))
				if b != null:
					if auto.get_slice(":", 2) == "hover":
						b.mouse_entered.emit()
					else:
						b.pressed.emit()
				break
			if auto.begins_with("fight"):
				if steps >= max_steps:
					break
				var targets := controller.get_valid_targets("basic_attack")
				if targets.is_empty() or controller.current.ap <= 0:
					controller.player_end_turn()
				else:
					var tgt := targets[0]
					for t in targets:
						if t.hp < tgt.hp:
							tgt = t
					var aid := "heavy_attack" if controller.current.ap >= 2 and controller.rng.randf() < 0.5 else "basic_attack"
					if controller.player_execute(aid, tgt):
						steps += 1
					else:
						controller.player_end_turn()
				await get_tree().create_timer(0.5).timeout
				continue
			break
	Game.maybe_cli_capture()
