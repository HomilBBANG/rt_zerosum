@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "리깅" 탭. 캐릭터 Skeleton2D 리그를 직접 만든다 (assets/sprites/rig_<id>/rig.json)

const PANEL := preload("res://addons/rtz_rig_editor/rig_editor_panel.gd")
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
		if visible and panel.has_method("reload_list"):
			panel.reload_list()


func _get_plugin_name() -> String:
	return "리깅"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("Skeleton2D" if th.has_icon("Skeleton2D", "EditorIcons") else "Bone2D", "EditorIcons")
