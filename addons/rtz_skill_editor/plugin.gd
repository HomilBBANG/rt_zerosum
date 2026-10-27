@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "스킬 트리" 탭. 캐릭터마다 액티브·패시브 십자형 스킬 트리 노드 (data/skill_tree.json)

const PANEL := preload("res://addons/rtz_skill_editor/skill_editor_panel.gd")
var panel: Control


func _enter_tree() -> void:
	panel = PANEL.new()
	EditorInterface.get_editor_main_screen().add_child(panel)
	_make_visible(false)


func _exit_tree() -> void:
	if panel != null:
		panel.queue_free()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if panel != null:
		panel.visible = visible
		if visible and panel.has_method("reload_data"):
			panel.reload_data(true)   # 탭을 열 때마다 캐릭터·스킬 목록 다시 읽기 (편집 중인 노드는 유지)


func _get_plugin_name() -> String:
	return "스킬 트리"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("GraphEdit" if th.has_icon("GraphEdit", "EditorIcons") else "Tree", "EditorIcons")
