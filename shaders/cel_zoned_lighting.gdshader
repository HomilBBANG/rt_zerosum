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

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float zone = texture(zone_mask, UV).r;
	vec3 out_rgb;
	if (zone < 0.17) {
		out_rgb = base.rgb * shadow_tint.rgb;
	} else if (zone < 0.45) {
		out_rgb = base.rgb * ambient_tint.rgb;
	} else if (zone < 0.55) {
		out_rgb = base.rgb * unlit_dim;
	} else if (zone < 0.83) {
		out_rgb = mix(base.rgb, key_color.rgb, key_mix);
	} else {
		out_rgb = mix(base.rgb, accent_color.rgb, accent_mix);
	}
	out_rgb = mix(out_rgb, flash_color.rgb, flash_color.a);
	COLOR = vec4(out_rgb, base.a);
}
