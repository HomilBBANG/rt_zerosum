extends SceneTree
## 스킬 표 data/skills.xlsx 다시 쓰기: godot --headless --path . -s tools/skill_table.gd
## 지금 데이터(JSON + 표 값)를 그대로 표로 — 에디터에서 새로 만든 노드 · 스킬이 표에 줄로 생기고, (참고) 열이 새로 채워짐.
## (평소엔 Godot 에디터 '스킬 트리' 탭에서 저장하면 같이 다시 써짐)


func _initialize() -> void:
	var err := SkillTable.write()
	print("스킬 표 → %s (%s)" % [ProjectSettings.globalize_path(SkillTable.PATH), "OK" if err == OK else "실패 %d — 엑셀에 열려 있으면 닫고 다시" % err])
	quit(0 if err == OK else 1)
