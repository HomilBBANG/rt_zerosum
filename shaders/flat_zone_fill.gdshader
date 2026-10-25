// 단색 도형(Polygon2D/ColorRect)에 구역 코드 하나를 적용: 조명 프리셋 변경 시 자동 재착색.
shader_type canvas_item;
render_mode unshaded;
uniform int zone : hint_range(0, 4) = 1; // 0 shadow 1 ambient 2 unlit 3 key 4 accent
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float key_mix : hint_range(0.0, 1.0) = 0.7;
uniform float accent_mix : hint_range(0.0, 1.0) = 0.8;
void fragment() {
	// Godot 4: fragment 의 COLOR 는 이미 텍스처색 × 정점색(모듈레이트) → 한 번만 곱한 원화색
	vec4 base = COLOR;
	vec3 o = base.rgb;
	if (zone == 0) { o = base.rgb * shadow_tint.rgb; }
	else if (zone == 1) { o = base.rgb * ambient_tint.rgb; }
	else if (zone == 3) { o = mix(base.rgb, key_color.rgb, key_mix); }
	else if (zone == 4) { o = mix(base.rgb, accent_color.rgb, accent_mix); }
	COLOR = vec4(o, base.a);
}
