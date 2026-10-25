// 캐릭터 전용 셀 라이팅 (배경은 cel_zoned_lighting).
// 고유색 × 광원색(곱하기) + 약한 광원색 가산 + 채도 보정으로 색을 '입힌다' (덮어 섞으면 반투명 막처럼 보임).
// zone_mask: 0 그림자 / 85 주변광 / 128 고유색 유지(눈) / 170 주조명 / 255 림(보조광)
// 마스크는 구역 코드라 보간할 수 없으므로(최근접), 화면 픽셀 안에서 4번 샘플해 결과 색을 평균 → 명암 경계 계단 제거.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D zone_mask : filter_nearest, repeat_disable;
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float key_mix : hint_range(0.0, 1.0) = 0.6;
uniform float accent_mix : hint_range(0.0, 1.0) = 0.85;
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.22;
uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

vec3 tinted(vec3 base, vec3 light, float strength, float gain, float add) {
	vec3 filt = mix(vec3(1.0), light, strength);
	return clamp(base * filt * gain + light * add, 0.0, 1.0);
}

vec3 shade(vec3 base, float zone) {
	if (zone < 0.17) {
		vec3 sh = shadow_tint.rgb * 2.2 + vec3(shadow_lift);
		return clamp(base * sh * 0.75 + shadow_tint.rgb * 0.08, 0.0, 1.0);
	} else if (zone < 0.45) {
		return tinted(base, ambient_tint.rgb, 0.55, 1.0, 0.04);
	} else if (zone < 0.55) {
		return base;
	} else if (zone < 0.83) {
		return tinted(base, key_color.rgb, key_mix, 1.25, 0.10);
	}
	return mix(base, accent_color.rgb, accent_mix);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 d = fwidth(UV) * 0.25;
	vec3 o = shade(base.rgb, texture(zone_mask, UV + vec2(-d.x, -d.y)).r)
		+ shade(base.rgb, texture(zone_mask, UV + vec2(d.x, -d.y)).r)
		+ shade(base.rgb, texture(zone_mask, UV + vec2(-d.x, d.y)).r)
		+ shade(base.rgb, texture(zone_mask, UV + vec2(d.x, d.y)).r);
	o *= 0.25;
	float l = dot(o, vec3(0.299, 0.587, 0.114));
	o = clamp(mix(vec3(l), o, saturation), 0.0, 1.0);
	o = mix(o, flash_color.rgb, flash_color.a);
	COLOR = vec4(o, base.a);
}
