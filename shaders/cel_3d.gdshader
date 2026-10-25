// Godot 4.7 spatial cel shader — 2D cel_zoned_lighting 과 같은 4구역 규칙을 실광원으로 재현.
//  빛이 전혀 닿지 않음(차폐)          = base * shadow_tint        (그림자 구역)
//  약한 채움광(에너지 < 0.6)이 닿음     = base * ambient_tint       (주변광 구역)
//  강한 색광원(키/보조)이 닿음         = mix(base, 광원색, light_mix) (키/보조광 구역, 하드 에지)
shader_type spatial;
render_mode cull_back, depth_draw_opaque, specular_disabled, ambient_light_disabled;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap;
uniform bool use_tex = false;
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform float light_mix : hint_range(0.0, 1.0) = 0.7;
uniform float threshold : hint_range(0.0, 1.0) = 0.10;
uniform float fill_threshold : hint_range(0.0, 1.0) = 0.03;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);

void fragment() {
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	ALBEDO = base;
	EMISSION = mix(base * shadow_tint.rgb, flash_color.rgb, flash);
}

void light() {
	float peak = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float strength = peak / 3.14159;
	vec3 lcol = LIGHT_COLOR / max(peak, 0.0001);
	float band = dot(NORMAL, LIGHT) * ATTENUATION;
	vec3 shadow_part = ALBEDO * shadow_tint.rgb;
	vec3 ambient_part = ALBEDO * ambient_tint.rgb;
	if (strength < 0.6) {
		// 채움광(방향광, 그림자 O): 그림자 구역 → 주변광 구역
		float lit = step(fill_threshold, band);
		DIFFUSE_LIGHT += lit * (ambient_part - shadow_part);
	} else {
		// 색광원: 주변광 구역을 '덮어써서' 광원색이 되도록 (주변광 몫을 빼서 가산 누적을 상쇄 — 채도 유지)
		float lit = step(threshold, band * min(strength, 2.0));
		vec3 target = mix(ALBEDO, lcol, light_mix);
		DIFFUSE_LIGHT += lit * (target - ambient_part);
	}
}
