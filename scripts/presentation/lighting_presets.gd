class_name LightingPresets
extends RefCounted
## 조명 프리셋 (02_graphics_implementation v0.2 §6 G1~G4 시연용 색 조합). 확정 팔레트 아님.

const ORDER := ["g1", "g2", "g3", "g4"]


static func get_preset(id: String) -> Dictionary:
	match id:
		"g2":
			return {
				"id": "g2", "name": "G2 초록 + 강한 빨강", "ref": "레퍼런스 3",
				"shadow": Color(0.03, 0.10, 0.05), "ambient": Color(0.36, 0.78, 0.42),
				"key": Color(1.0, 0.10, 0.12), "accent": Color(0.78, 1.0, 0.25),
				"key_mix": 0.72, "accent_mix": 0.78, "char_key_mix": 0.55, "char_accent_mix": 0.7,
				"clear": Color(0.02, 0.06, 0.03),
				"ui_accent": Color(1.0, 0.85, 0.3),
			}
		"g3":
			return {
				"id": "g3", "name": "G3 남청 + 주황", "ref": "레퍼런스 4",
				"shadow": Color(0.03, 0.05, 0.20), "ambient": Color(0.24, 0.42, 0.88),
				"key": Color(1.0, 0.52, 0.06), "accent": Color(0.40, 0.82, 1.0),
				"key_mix": 0.72, "accent_mix": 0.75, "char_key_mix": 0.58, "char_accent_mix": 0.65,
				"clear": Color(0.02, 0.03, 0.12),
				"ui_accent": Color(1.0, 0.75, 0.35),
			}
		"g4":
			return {
				"id": "g4", "name": "G4 보라 + 시안/마젠타", "ref": "레퍼런스 2",
				"shadow": Color(0.08, 0.03, 0.17), "ambient": Color(0.56, 0.34, 0.88),
				"key": Color(0.18, 0.95, 1.0), "accent": Color(1.0, 0.30, 0.92),
				"key_mix": 0.68, "accent_mix": 0.75, "char_key_mix": 0.52, "char_accent_mix": 0.65,
				"clear": Color(0.05, 0.02, 0.10),
				"ui_accent": Color(0.9, 1.0, 0.5),
			}
		_:
			return {
				"id": "g1", "name": "G1 청록 + 핑크", "ref": "레퍼런스 1",
				"shadow": Color(0.05, 0.16, 0.18), "ambient": Color(0.40, 0.74, 0.72),
				"key": Color(1.0, 0.12, 0.47), "accent": Color(0.22, 1.0, 0.73),
				"key_mix": 0.72, "accent_mix": 0.78, "char_key_mix": 0.55, "char_accent_mix": 0.7,
				"clear": Color(0.02, 0.06, 0.07),
				"ui_accent": Color(1.0, 0.9, 0.4),
			}


static func next_id(id: String) -> String:
	var i := ORDER.find(id)
	return ORDER[(i + 1) % ORDER.size()]


static func apply_to_material(mat: ShaderMaterial, p: Dictionary, key_mix: float = -1.0, accent_mix: float = -1.0) -> void:
	mat.set_shader_parameter("shadow_tint", p.shadow)
	mat.set_shader_parameter("ambient_tint", p.ambient)
	mat.set_shader_parameter("key_color", p.key)
	mat.set_shader_parameter("accent_color", p.accent)
	mat.set_shader_parameter("key_mix", p.key_mix if key_mix < 0.0 else key_mix)
	mat.set_shader_parameter("accent_mix", p.accent_mix if accent_mix < 0.0 else accent_mix)
