// 캐릭터 셀 라이팅 v6 — "원화 색 또렷 + 타지 않는 빛 + 선화·검정 보존".
// 원화의 밝기(명암)는 픽셀마다 그대로 두고 '색상'만 조명 쪽으로 옮긴다.
// (곱하기는 보색 조명에서 원화를 어둡게 죽이고, 스크린은 어두운 의상에 회색 막을 씌워 둘 다 쓰지 않음)
//   빛 받는 면 : 원화 밝기를 살짝(어두운 색일수록 더) 올리고 광원 색상으로 key_mix 만큼 옮긴다.
//               밝은 색이 하얗게 날아가지 않게 채널이 1 을 넘으면 색상을 유지한 채 전체를 낮춘다(클리핑·채도 과장 없음).
//               빛은 '검정이 아닌 색'에만: 선화(주변보다 확 어두운 선)와 검정(부츠·검정 티 등)은 원화 그대로.
//   주변광     : 원화 그대로
//   그림자     : 원화 밝기의 82% + 그림자 색상 쪽으로 약간(18%) — 그림자 속에서도 고유색이 보이게
//   림         : 조명색 선 (선화 제외)
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
uniform float key_mix : hint_range(0.0, 1.0) = 0.55;      // 빛 받는 면을 광원 색상으로 덮는 정도 (1 = 광원색으로 완전히 칠함)
uniform float accent_mix : hint_range(0.0, 1.0) = 0.85;   // 림 세기
uniform float shadow_depth : hint_range(0.3, 1.0) = 0.82; // 그림자 밝기 (원화 대비)
uniform float shadow_hue : hint_range(0.0, 1.0) = 0.18;   // 그림자를 그림자 색상으로 옮기는 정도
uniform float ambient_mix : hint_range(0.0, 1.0) = 0.0;  // 주변광 구역의 색 물듦
uniform float light_lift : hint_range(0.0, 0.5) = 0.12;   // 빛 받는 면을 밝히는 양 (남은 밝기 여유의 비율: 어두운 색일수록 많이)
uniform vec2 black_range = vec2(0.09, 0.20);   // 이 밝기 아래는 '검정'으로 보고 빛을 입히지 않음 (사이 구간은 서서히)
uniform vec2 line_ratio = vec2(0.55, 0.80);   // 주변 평균 밝기 대비 이 비율보다 어두운 픽셀 = 선화 → 빛을 입히지 않음
uniform float line_radius = 2.5;               // 주변 평균을 볼 거리 (텍셀)
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform bool use_rim = true;
uniform vec4 eye_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
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

// 채널이 1 을 넘으면 잘라내지 않고(=색이 하얗게 타고 색상이 틀어짐) 색상 비율을 유지한 채 낮춘다
vec3 no_burn(vec3 c) {
	return c / max(1.0, max(c.r, max(c.g, c.b)));
}

// 선화 가중치: 1 = 칠한 면, 0 = 선화. 절대 밝기가 아니라 '주변보다 확 어두운가'로 판단해서
// 검정 의상처럼 원래 어두운 면에도 빛은 입히고, 그 위의 선(윤곽·주름)만 남긴다. 빛·림은 칠한 면에만.
float line_weight(sampler2D tex, vec2 uv, vec2 texel, float L) {
	float sum = 0.0;
	float wsum = 0.0;
	for (int i = 0; i < 8; i++) {
		float ang = 6.2831853 * float(i) / 8.0;
		vec4 t = texture(tex, uv + vec2(cos(ang), sin(ang)) * texel * line_radius);
		sum += lum(t.rgb) * t.a;
		wsum += t.a;
	}
	float avg = sum / max(wsum, 0.001);
	float r = L / max(avg, 0.03);
	return smoothstep(line_ratio.x, line_ratio.y, r) * smoothstep(0.015, 0.05, L);
}

vec3 shade(vec3 base, float zone, float lw) {
	float L = lum(base);
	if (zone < 0.17 || (zone >= 0.83 && !use_rim)) {
		return clamp(mix(base, tint_keep_L(shadow_tint.rgb, L), shadow_hue) * shadow_depth, 0.0, 1.0);
	} else if (zone < 0.45) {
		return clamp(mix(base, tint_keep_L(ambient_tint.rgb, L), ambient_mix), 0.0, 1.0);
	} else if (zone < 0.55) {
		vec3 e = eye_color.rgb * (L / max(lum(eye_color.rgb), 0.05)) * 1.35;
		e = mix(e, e * mix(vec3(1.0), key_color.rgb, 0.5), 0.12);
		return clamp(e, 0.0, 1.0);
	} else if (zone < 0.83) {
		float Ll = L + (1.0 - L) * light_lift;
		vec3 lit = mix(no_burn(base * (Ll / max(L, 0.001))), no_burn(tint_keep_L(key_color.rgb, Ll)), key_mix);
		return mix(base, lit, lw);
	}
	return mix(base, accent_color.rgb, accent_mix * lw);
}

vec3 shade2(vec3 base, vec2 uv, float lw) {
	vec3 c = shade(base, texture(zone_mask, uv).r, lw);
	if (use_near_rim && texture(near_rim_mask, uv).r >= 0.83) {
		c = mix(c, near_rim_color.rgb, near_rim_mix * lw);
	}
	return c;
}

void fragment() {
	// Godot 4: fragment 의 COLOR 는 이미 텍스처색 × 정점색(모듈레이트). 다시 텍스처를 곱하면 색이 제곱돼 어두워진다.
	vec4 base = COLOR;
	// 빛·림을 입힐 가중치: 선화가 아니고(주변 대비) 검정도 아닌(절대 밝기) 픽셀만
	float lw = line_weight(TEXTURE, UV, TEXTURE_PIXEL_SIZE, lum(base.rgb)) * smoothstep(black_range.x, black_range.y, lum(base.rgb));
	vec2 d = fwidth(UV) * 0.25;
	vec3 o = shade2(base.rgb, UV + vec2(-d.x, -d.y), lw)
		+ shade2(base.rgb, UV + vec2(d.x, -d.y), lw)
		+ shade2(base.rgb, UV + vec2(-d.x, d.y), lw)
		+ shade2(base.rgb, UV + vec2(d.x, d.y), lw);
	o *= 0.25;
	float l = lum(o);
	o = clamp(mix(vec3(l), o, saturation), 0.0, 1.0);
	o = mix(o, flash_color.rgb, flash_color.a);
	if (debug_view == 1) {
		o = base.rgb;
	}
	COLOR = vec4(o, base.a);
}
