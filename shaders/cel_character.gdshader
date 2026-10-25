// 캐릭터 셀 라이팅 v4 — "원화 보전 + 쨍한 명암".
// 원화의 밝기(명암)는 픽셀마다 그대로 두고 '색상'만 조명 쪽으로 옮긴다.
// (곱하기는 보색 조명에서 원화를 어둡게 죽이고, 스크린은 어두운 의상에 회색 막을 씌워 둘 다 쓰지 않음)
//   빛 받는 면 : 원화 밝기 유지 + 광원 색상 쪽으로 이동 + 15% 밝게 + 광원색 소량 더함(검정 옷에도 빛이 맺힘)
//   주변광     : 원화 거의 그대로 (8% 물듦)
//   그림자     : 원화 밝기의 78% + 그림자 색상 쪽으로 40% 이동 (셀 경계는 마스크로 하드 에지)
//   림         : 반대 조명색 선
//   눈동자     : eye_color 로 진하게
// zone_mask: 0 그림자 / 85 주변광 / 128 눈동자 / 170 주조명 / 255 림
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D zone_mask : filter_nearest, repeat_disable;
// 반대 방향 마스크: 그 림(255) 구역이 '빛 쪽' 가장자리에 해당 → 빛 쪽 몸을 밝히면서 같은 쪽 가장자리에 림을 더할 때 사용
uniform sampler2D near_rim_mask : filter_nearest, repeat_disable;
uniform bool use_near_rim = false;
uniform vec4 near_rim_color : source_color = vec4(1.0);
uniform float near_rim_mix : hint_range(0.0, 1.0) = 0.85;
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float key_mix : hint_range(0.0, 1.0) = 0.6;       // 빛 받는 면에 광원색을 얹는 세기
uniform float accent_mix : hint_range(0.0, 1.0) = 0.85;   // 림 세기
uniform float shadow_depth : hint_range(0.3, 1.0) = 0.78; // 그림자 밝기 (원화 대비)
uniform float shadow_hue : hint_range(0.0, 1.0) = 0.40;   // 그림자를 그림자 색상으로 옮기는 정도
uniform float ambient_mix : hint_range(0.0, 1.0) = 0.08;  // 주변광 구역의 색 물듦
uniform float lit_gain : hint_range(0.8, 1.5) = 1.15;     // 빛 받는 면 밝기
uniform float light_lift : hint_range(0.0, 0.5) = 0.20;   // 빛 받는 면에 광원색을 더하는 양 (어두운 의상도 빛이 '맺히게')
uniform float saturation : hint_range(0.0, 2.0) = 1.18;
uniform bool use_rim = true;
uniform vec4 eye_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform bool paint_eyes = true;   // false: 눈동자를 칠하지 않고 주변광 구역처럼 (원화 눈 색)
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform int debug_view = 0;   // 1: 원화 그대로 출력 (디버그)

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 hue_of(vec3 c) {   // 밝기를 1 로 맞춘 색상 (어두운 그림자색도 색상만 쓰기 위해)
	return c / max(max(c.r, max(c.g, c.b)), 0.001);
}

// 원화 픽셀 밝기 L 은 그대로 두고 색상만 c 로 바꾼 색
vec3 tint_keep_L(vec3 c, float L) {
	vec3 h = hue_of(c);
	return h * (L / max(lum(h), 0.001));
}

vec3 shade(vec3 base, float zone) {
	float L = lum(base);
	if (zone < 0.17 || (zone >= 0.83 && !use_rim)) {
		return clamp(mix(base, tint_keep_L(shadow_tint.rgb, L), shadow_hue) * shadow_depth, 0.0, 1.0);
	} else if (zone < 0.45) {
		return clamp(mix(base, tint_keep_L(ambient_tint.rgb, L), ambient_mix), 0.0, 1.0);
	} else if (zone < 0.55) {
		if (!paint_eyes) {
			return clamp(mix(base, tint_keep_L(ambient_tint.rgb, L), ambient_mix), 0.0, 1.0);
		}
		vec3 e = eye_color.rgb * (L / max(lum(eye_color.rgb), 0.05)) * 1.35;
		e = mix(e, e * mix(vec3(1.0), key_color.rgb, 0.5), 0.12);
		return clamp(e, 0.0, 1.0);
	} else if (zone < 0.83) {
		vec3 lit = mix(base, tint_keep_L(key_color.rgb, L), key_mix * 0.55) * lit_gain;
		return clamp(lit + key_color.rgb * key_mix * light_lift, 0.0, 1.0);
	}
	return mix(base, accent_color.rgb, accent_mix);
}

vec3 shade2(vec3 base, vec2 uv) {
	vec3 c = shade(base, texture(zone_mask, uv).r);
	if (use_near_rim && texture(near_rim_mask, uv).r >= 0.83) {
		c = mix(c, near_rim_color.rgb, near_rim_mix);
	}
	return c;
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 d = fwidth(UV) * 0.25;
	vec3 o = shade2(base.rgb, UV + vec2(-d.x, -d.y))
		+ shade2(base.rgb, UV + vec2(d.x, -d.y))
		+ shade2(base.rgb, UV + vec2(-d.x, d.y))
		+ shade2(base.rgb, UV + vec2(d.x, d.y));
	o *= 0.25;
	float l = lum(o);
	o = clamp(mix(vec3(l), o, saturation), 0.0, 1.0);
	o = mix(o, flash_color.rgb, flash_color.a);
	if (debug_view == 1) {
		o = base.rgb;
	}
	COLOR = vec4(o, base.a);
}
