@tool
extends EditorPlugin
## Godot 에디터 상단(2D · 3D · Script 옆)의 "전투 발생" 탭. 기지 시간에 따라 전투가 일어나는 규칙 (data/outgame/battle_rules.json)

const PANEL := preload("res://addons/rtz_battle_editor/battle_editor_panel.gd")
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
			panel.reload_data(true)   # 탭을 열 때마다 스테이지 목록·시작 시각 다시 읽기 (편집 중인 규칙은 유지)


func _get_plugin_name() -> String:
	return "전투 발생"


func _get_plugin_icon() -> Texture2D:
	var th := EditorInterface.get_editor_theme()
	return th.get_icon("Timer" if th.has_icon("Timer", "EditorIcons") else "Time", "EditorIcons")
