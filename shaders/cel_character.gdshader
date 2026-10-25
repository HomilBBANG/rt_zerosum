// 캐릭터 전용 셀 라이팅 (배경은 cel_zoned_lighting).
// 고유색 × 광원색(곱하기) + 약한 광원색 가산 + 채도 보정으로 색을 '입힌다' (덮어 섞으면 반투명 막처럼 보임).
// zone_mask: 0 그림자 / 85 주변광 / 170 주조명 / 255 림(보조광)  (128 은 배경 전용, 캐릭터에서는 주조명 취급)
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
uniform bool use_rim = true;   // false: 림 구역을 그림자로 (림 라인 없음)
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// 고유색에 빛 색을 곱해 입힌 뒤, 밝기는 원화의 명암을 따르게 맞춘다.
// → 색은 조명색으로 쨍하게 바뀌지만 눈썹·눈동자·턱선 같은 원화의 명암 차이는 그대로 남는다(선 없는 원화도 이목구비 유지).
vec3 tinted(vec3 base, vec3 light, float strength, float target_lum, float add) {
	vec3 filt = mix(vec3(1.0), light, strength);
	vec3 t = base * filt + light * add;
	t *= target_lum / max(lum(t), 0.02);
	return clamp(t, 0.0, 1.0);
}

vec3 shade(vec3 base, float zone) {
	float L = lum(base);
	if (zone < 0.17 || (zone >= 0.83 && !use_rim)) {
		// 그림자: 그림자색으로 물들되 원화 명암의 약 절반 밝기 (검정으로 뭉개지지 않게)
		return tinted(base, shadow_tint.rgb * 2.5 + vec3(0.1), 0.85, L * 0.42 + shadow_lift * 0.12, 0.0);
	} else if (zone < 0.45) {
		return tinted(base, ambient_tint.rgb, 0.55, L * 0.95, 0.02);
	} else if (zone < 0.83) {
		// 주조명 (0.45~0.55 의 '고유색 유지' 구역도 주조명으로 처리: 눈만 따로 튀지 않게)
		return tinted(base, key_color.rgb, key_mix, L * 1.08 + 0.04, 0.06);
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
