@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "AI" 탭. 몬스터 AI 노드 에디터 (data/ai/*.json)

const PANEL := preload("res://addons/rtz_ai_editor/ai_editor_panel.gd")
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


func _get_plugin_name() -> String:
	return "AI"


func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_editor_theme().get_icon("GraphEdit", "EditorIcons")

