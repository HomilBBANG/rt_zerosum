extends SceneTree
## 스킬 트리 에디터 내용을 엑셀로: godot --headless --path . -s tools/export_skills_xlsx.gd [출력.xlsx]
## 기본 출력 = exports/skills.xlsx (Godot 에디터 '스킬 트리' 탭 '엑셀로 내보내기' 버튼과 같은 내용)


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if not args.is_empty() else SkillExport.DEFAULT_PATH
	var err := SkillExport.export(path)
	print("스킬 엑셀 내보내기 → %s (%s)" % [ProjectSettings.globalize_path(path), "OK" if err == OK else "실패 %d" % err])
	quit(0 if err == OK else 1)
