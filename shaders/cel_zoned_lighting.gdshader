// Godot 4.7 CanvasItem shader: full-color sprite + zoned lighting mask (v0.3).
// zone_mask grayscale: 0=shadow, 85=ambient, 128=unlit(고유색 유지: 눈·발광부), 170=key, 255=accent(rim/보조광).
// v0.3 변경: 128 '고유색 유지' 구역 추가 (가독성용), 나머지는 v0.2 원안과 동일.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D zone_mask : filter_nearest, repeat_disable;
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float key_mix : hint_range(0.0, 1.0) = 0.7;
uniform float accent_mix : hint_range(0.0, 1.0) = 0.8;
uniform float unlit_dim : hint_range(0.0, 1.0) = 0.9;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0); // 피격 플래시 (a = 강도)

vec3 zone_color(vec3 base, float zone) {
	if (zone < 0.17) {
		return base * shadow_tint.rgb;
	} else if (zone < 0.45) {
		return base * ambient_tint.rgb;
	} else if (zone < 0.55) {
		return base * unlit_dim;
	} else if (zone < 0.83) {
		return mix(base, key_color.rgb, key_mix);
	}
	return mix(base, accent_color.rgb, accent_mix);
}

void fragment() {
	// Godot 4: fragment 의 COLOR 는 이미 텍스처색 × 정점색(모듈레이트) → 한 번만 곱한 원화색
	vec4 base = COLOR;
	// 구역 코드는 보간 불가(최근접) → 화면 픽셀 안 4점의 결과 색을 평균해 경계 계단 제거 (v0.4)
	vec2 d = fwidth(UV) * 0.25;
	vec3 out_rgb = zone_color(base.rgb, texture(zone_mask, UV + vec2(-d.x, -d.y)).r)
		+ zone_color(base.rgb, texture(zone_mask, UV + vec2(d.x, -d.y)).r)
		+ zone_color(base.rgb, texture(zone_mask, UV + vec2(-d.x, d.y)).r)
		+ zone_color(base.rgb, texture(zone_mask, UV + vec2(d.x, d.y)).r);
	out_rgb *= 0.25;
	out_rgb = mix(out_rgb, flash_color.rgb, flash_color.a);
	COLOR = vec4(out_rgb, base.a);
}
