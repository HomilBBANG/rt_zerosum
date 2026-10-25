class_name TestRoster
extends RefCounted
## 프로토타입 임시 테스트 데이터 (GDD 3절). 최종 밸런스 아님.


static func _action(id: String, name: String, kind: String, cost: int, rule: String, effect: String, power: int, desc: String) -> ActionData:
	var a := ActionData.new()
	a.id = id
	a.display_name = name
	a.kind = kind
	a.ap_cost = cost
	a.target_rule = rule
	a.effect = effect
	a.power = power
	a.description = desc
	return a


static func build_actions() -> Dictionary:
	var list: Array[ActionData] = [
		_action("basic_attack", "기본 공격", "attack", 1, "weapon", "damage", 6, "현재 무기로 공격. 근접: 상대 앞열 우선 / 원거리: 전열 무관"),
		_action("heavy_attack", "강공격", "heavy", 2, "weapon", "damage", 11, "현재 무기로 강하게 공격"),
		_action("heal", "응급 처치", "support", 2, "ally_any", "heal", 10, "아군 1명 HP 회복"),
		_action("rally", "독려", "support", 2, "ally_other", "ap_grant", 2, "다른 아군 1명 AP +2 (상한까지)"),
		_action("ultimate", "필살기", "ultimate", 4, "enemy_any", "damage", 18, "열 무관 강력한 일격"),
		_action("move", "위치 변경", "move", 1, "slot", "move", 0, "빈 슬롯 이동 / 점유 슬롯 아군과 교환"),
		_action("weapon", "무기 변경", "weapon", 1, "none", "weapon_swap", 0, "보조 무기로 교체 (사거리 변경)"),
	]
	var d := {}
	for a in list:
		d[a.id] = a
	return d


static func _unit(id: String, name: String, team: String, role: String, lvl: int, spd: int, rtype: String,
		hp: int, ap: int, rec: int, dfn: int, skills: Array, weapons: Array, row: int, idx: int, palette: Dictionary) -> UnitData:
	var u := UnitData.new()
	u.id = id
	u.display_name = name
	u.team = team
	u.role = role
	u.level = lvl
	u.speed = spd
	u.range_type = rtype
	u.max_hp = hp
	u.max_ap = ap
	u.ap_recovery = rec
	u.defense = dfn
	var s: Array[String] = []
	for x in skills:
		s.append(x)
	u.skill_ids = s
	var w: Array[Dictionary] = []
	for x in weapons:
		w.append(x)
	u.weapons = w
	u.sprite_id = palette.get("sprite_id", id)
	u.height_cm = float(palette.get("height_cm", 175.0))
	u.default_row = row
	u.default_index = idx
	u.palette = palette
	return u


static func W(id: String, name: String, rtype: String, bonus: int) -> Dictionary:
	return {"id": id, "name": name, "range_type": rtype, "power_bonus": bonus}


static func build_allies() -> Array[UnitData]:
	var out: Array[UnitData] = [
		_unit("a_jiho", "지호", "ally", "돌격병", 5, 9, "melee", 40, 6, 2, 1,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("axe", "전투도끼", "melee", 2), W("shotgun", "산탄총", "ranged", 0)], 0, 0,
			{"skin": "#f4c9a4", "hair": "#2b1d16", "jacket": "#3b5d4a", "pants": "#2a3340", "accent": "#ffb347", "eyes": "#4a86c8", "hair_style": "spiky"}),
		_unit("a_sera", "세라", "ally", "방패병", 4, 6, "melee", 44, 5, 3, 2,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("baton", "진압봉", "melee", 1), W("pistol", "권총", "ranged", -1)], 0, 1,
			{"skin": "#f8d6c2", "hair": "#e8c178", "jacket": "#4e6b8a", "pants": "#2d2f3a", "accent": "#ff5e8a", "eyes": "#3aa66e", "hair_style": "bob"}),
		_unit("a_minu", "민우", "ally", "소총수", 5, 8, "ranged", 30, 6, 2, 0,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("rifle", "소총", "ranged", 1), W("bayonet", "대검", "melee", 2)], 1, 0,
			{"skin": "#e9b68f", "hair": "#141414", "jacket": "#5b6652", "pants": "#30353a", "accent": "#62d3ff", "eyes": "#7a4b2a", "hair_style": "short"}),
		_unit("a_haneul", "하늘", "ally", "의무병", 3, 7, "ranged", 28, 7, 3, 0,
			["basic_attack", "heal", "rally", "ultimate"],
			[W("pistol", "권총", "ranged", 0), W("syringe", "전투 주사기", "melee", 1)], 1, 1,
			{"skin": "#fbe3d0", "hair": "#c4553a", "jacket": "#e9e4d6", "pants": "#3a4652", "accent": "#ff3b5c", "eyes": "#2f7fd3", "hair_style": "ponytail"}),
		_unit("a_raon", "라온", "ally", "저격수", 6, 11, "ranged", 24, 5, 2, 0,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("sniper", "저격총", "ranged", 3), W("knife", "단검", "melee", 0)], 2, 0,
			{"skin": "#f4cdb6", "hair": "#8a2f22", "jacket": "#c4bcba", "pants": "#4a4240", "accent": "#d9d9e0", "eyes": "#6a6f78", "hair_style": "long", "sprite_id": "nikita_army"}),
		_unit("a_doyun", "도윤", "ally", "통신병", 5, 9, "ranged", 26, 8, 3, 0,
			["basic_attack", "rally", "heal", "ultimate"],
			[W("smg", "기관단총", "ranged", 0), W("club", "곤봉", "melee", 1)], 2, 1,
			{"skin": "#f3cdb3", "hair": "#8a5a2b", "jacket": "#6b5f8e", "pants": "#2c2a3a", "accent": "#ffe45e", "eyes": "#4c4c4c", "hair_style": "curly"}),
	]
	return out


static func build_enemies() -> Array[UnitData]:
	var out: Array[UnitData] = [
		_unit("e_captain", "돌격대장", "enemy", "돌격병", 6, 10, "melee", 42, 6, 2, 1,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("blade", "군도", "melee", 2)], 0, 0,
			{"skin": "#d9b08c", "hair": "#111111", "jacket": "#7a1f2b", "pants": "#1f1f24", "accent": "#ffd23f", "eyes": "#d8463c", "hair_style": "short"}),
		_unit("e_grenadier", "척탄병", "enemy", "척탄병", 4, 7, "melee", 38, 5, 2, 2,
			["basic_attack", "heavy_attack"],
			[W("mace", "철퇴", "melee", 1), W("launcher", "유탄 발사기", "ranged", 1)], 0, 1,
			{"skin": "#c99a76", "hair": "#4a2d1b", "jacket": "#6a2230", "pants": "#26242b", "accent": "#ff8c42", "eyes": "#5a3b2e", "hair_style": "bald"}),
		_unit("e_rifle", "소총병", "enemy", "소총수", 5, 9, "ranged", 30, 6, 2, 0,
			["basic_attack", "heavy_attack"],
			[W("rifle", "소총", "ranged", 1)], 1, 0,
			{"skin": "#e4b393", "hair": "#2a1a12", "jacket": "#8a2634", "pants": "#2b2630", "accent": "#ff5c5c", "eyes": "#3b2f2f", "hair_style": "short"}),
		_unit("e_gunner", "기관총사수", "enemy", "중화기", 5, 5, "ranged", 36, 5, 2, 1,
			["basic_attack", "heavy_attack"],
			[W("mg", "기관총", "ranged", 2)], 1, 1,
			{"skin": "#bf8e6e", "hair": "#1a1a1a", "jacket": "#5e1e2a", "pants": "#22212a", "accent": "#ffb86b", "eyes": "#2a2a2a", "hair_style": "spiky"}),
		_unit("e_sniper", "저격수", "enemy", "저격수", 6, 12, "ranged", 24, 5, 2, 0,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("sniper", "저격총", "ranged", 3)], 2, 0,
			{"skin": "#f0cdb4", "hair": "#d6d6e0", "jacket": "#4a1b2c", "pants": "#1d1c26", "accent": "#ff2e7a", "eyes": "#b23a9e", "hair_style": "long"}),
		_unit("e_commander", "지휘관", "enemy", "지휘관", 7, 8, "ranged", 32, 7, 3, 1,
			["basic_attack", "heal", "rally", "ultimate"],
			[W("pistol", "권총", "ranged", 0)], 2, 1,
			{"skin": "#e8c4a8", "hair": "#6b4a2b", "jacket": "#9a2b3f", "pants": "#2b2230", "accent": "#ffd700", "eyes": "#2f4f8f", "hair_style": "bob"}),
	]
	return out


## 사용자 제공 원화 캐릭터만으로 구성한 전투 (게임 기본). 같은 두 캐릭터를 적으로도 세운다.
## 생성 원화 12인(build_allies/build_enemies)은 규칙 테스트·벤치용으로만 유지.
static func build_provided_allies() -> Array[UnitData]:
	var out: Array[UnitData] = [
		_unit("a_nikita", "니키타", "ally", "저격수", 6, 11, "ranged", 24, 5, 2, 0,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("sniper", "저격총", "ranged", 3), W("knife", "단검", "melee", 0)], 2, 1,
			{"skin": "#f4cdb6", "hair": "#8a2f22", "jacket": "#c4bcba", "pants": "#4a4240", "accent": "#d9d9e0", "eyes": "#6a6f78", "eye_paint": "#4f9cff", "hair_style": "long", "sprite_id": "nikita_army", "height_cm": 168.0}),
		_unit("a_hana", "하나", "ally", "돌격소총수", 5, 9, "ranged", 34, 6, 2, 1,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("rifle", "소총", "ranged", 1), W("bayonet", "대검", "melee", 2)], 0, 1,
			{"skin": "#c98a62", "hair": "#7a6455", "jacket": "#4a4342", "pants": "#463f3e", "accent": "#e8e4e0", "eyes": "#c99a3a", "eye_paint": "#ffb020", "hair_style": "ponytail", "sprite_id": "hero2", "height_cm": 176.8}),
	]
	return out


static func build_provided_enemies() -> Array[UnitData]:
	var out: Array[UnitData] = [
		_unit("e_hana", "적 돌격소총수", "enemy", "돌격소총수", 5, 10, "ranged", 34, 6, 2, 1,
			["basic_attack", "heavy_attack"],
			[W("rifle", "소총", "ranged", 1)], 0, 1,
			{"skin": "#c98a62", "hair": "#7a6455", "jacket": "#4a4342", "pants": "#463f3e", "accent": "#ff5c5c", "eyes": "#c99a3a", "eye_paint": "#ffb020", "hair_style": "ponytail", "sprite_id": "hero2", "height_cm": 176.8}),
		_unit("e_nikita", "적 저격수", "enemy", "저격수", 6, 12, "ranged", 24, 5, 2, 0,
			["basic_attack", "heavy_attack", "ultimate"],
			[W("sniper", "저격총", "ranged", 3)], 2, 1,
			{"skin": "#f4cdb6", "hair": "#8a2f22", "jacket": "#c4bcba", "pants": "#4a4240", "accent": "#ff2e7a", "eyes": "#6a6f78", "eye_paint": "#4f9cff", "hair_style": "long", "sprite_id": "nikita_army", "height_cm": 168.0}),
	]
	return out


static func find_unit(list: Array[UnitData], id: String) -> UnitData:
	for u in list:
		if u.id == id:
			return u
	return null


## 컨트롤러 setup 용 로스터 [{data,row,index}]
static func default_roster(allies: Array[UnitData], enemies: Array[UnitData]) -> Array:
	var out: Array = []
	for u in allies:
		out.append({"data": u, "row": u.default_row, "index": u.default_index})
	for u in enemies:
		out.append({"data": u, "row": u.default_row, "index": u.default_index})
	return out
