// 캐릭터 셀 라이팅 v7 — "장면 팔레트로 물드는 캐릭터 + 실제로 빛이 닿는 곳만 광원색".
// 목표 레퍼런스: 장면 전체가 '주변광 색상 하나 + 광원 색상 하나'로 칠해지고, 캐릭터도 그 팔레트로 물든다.
//   빛 없는 면 : 원화 밝기는 그대로, 색상을 주변광 색상 쪽으로 palette_mix 만큼 (선화도 같은 색상의 어두운 선이 됨)
//   형태 그림자: (빛 반대쪽 면) 그림자 색상 쪽으로 shadow_hue 만큼 + shadow_depth 만큼 어둡게
//   빛 받는 면 : 빛 지도(3D 광원을 캐릭터 몸 위에서 계산한 텍스처)가 밝은 곳만, 원화 밝기를 살짝 올리고
//               그 광원 색상으로 key_mix 만큼 칠함. 타지 않게(채널이 넘치면 색상 비율 유지한 채 낮춤).
//               선화(주변보다 확 어두운 선)와 검정(부츠·검정 티)은 빛을 받지 않음.
//   빛 쪽 가장자리 : 빛이 닿으면 광원색 림 (use_rim)
//   눈동자     : eye_color 로 진하게 (paint_eyes=false 면 원화 눈 색 그대로)
// zone_mask: 0 그림자면 / 85 경계띠 / 128 눈동자 / 170 빛 쪽 면 / 255 그림자 쪽 가장자리
// near_rim_mask: 반대 방향 마스크 — 그 255 구역이 빛 쪽 가장자리
// 빛 지도가 없으면(2D 배경 모드) 빛 쪽 면 전체를 key_color 로, 그림자 쪽 가장자리를 accent_color 림으로.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D zone_mask : filter_nearest, repeat_disable;
uniform sampler2D near_rim_mask : filter_nearest, repeat_disable;
uniform sampler2D light_map : filter_linear, repeat_disable, hint_default_black;
uniform bool use_light_map = false;
uniform vec4 lm_rect = vec4(0.0, 0.0, 1.0, 1.0);   // 빛 지도가 덮는 캔버스 영역 (왼쪽 위 x,y / 폭,높이)
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float palette_mix : hint_range(0.0, 1.0) = 0.55;  // 빛 없는 면이 주변광 색상으로 물드는 정도
uniform float shadow_hue : hint_range(0.0, 1.0) = 0.70;   // 형태 그림자면이 그림자 색상으로 물드는 정도
uniform float shadow_depth : hint_range(0.3, 1.0) = 0.80; // 형태 그림자면 밝기
uniform float key_mix : hint_range(0.0, 1.0) = 0.85;      // 빛 받는 면을 광원 색상으로 칠하는 정도
uniform float light_lift : hint_range(0.0, 0.6) = 0.35;   // 빛 받는 면을 밝히는 양 (남은 밝기 여유의 비율)
uniform float light_threshold : hint_range(0.0, 1.0) = 0.25; // 빛 지도 세기가 이보다 크면 '빛이 닿음' (하드 에지)
uniform bool use_rim = true;
uniform float near_rim_mix : hint_range(0.0, 1.0) = 0.85;
uniform float accent_mix : hint_range(0.0, 1.0) = 0.85;
uniform vec2 line_ratio = vec2(0.55, 0.80);   // 주변 평균 밝기 대비 이 비율보다 어두운 픽셀 = 선화 → 빛을 입히지 않음
uniform float line_radius = 2.5;               // 주변 평균을 볼 거리 (텍셀)
uniform vec2 black_range = vec2(0.09, 0.20);   // 이 밝기 아래는 '검정'으로 보고 빛을 입히지 않음
uniform vec4 eye_color : source_color = vec4(0.3, 0.6, 1.0, 1.0);
uniform bool paint_eyes = true;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform int debug_view = 0;   // 1: 원화 그대로 / 2: 빛 지도

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

vec3 hue_of(vec3 c) {   // 밝기를 1 로 맞춘 색상
	return c / max(max(c.r, max(c.g, c.b)), 0.001);
}

// 원화 픽셀 밝기 L 은 그대로 두고 색상만 c 로 바꾼 색
vec3 tint_keep_L(vec3 c, float L) {
	vec3 h = hue_of(c);
	return h * (L / max(lum(h), 0.001));
}

// 채널이 1 을 넘으면 잘라내지 않고 색상 비율을 유지한 채 낮춘다 (하얗게 타지 않게)
vec3 no_burn(vec3 c) {
	return c / max(1.0, max(c.r, max(c.g, c.b)));
}

// 선화 가중치: 1 = 칠한 면, 0 = 선화 (주변보다 확 어두운 픽셀)
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

// 광원색 칠: 밝기를 살짝 올리고 광원 색상으로
vec3 lit_color(vec3 base, float L, vec3 light_hue) {
	float Ll = L + (1.0 - L) * light_lift;
	return mix(no_burn(base * (Ll / max(L, 0.001))), no_burn(tint_keep_L(light_hue, Ll)), key_mix);
}

// lw: 빛을 받을 수 있는 픽셀(선화·검정 아님), lm: 이 위치에 닿는 빛 (색 × 세기)
vec3 shade(vec3 base, float zone, float near_zone, float lw, vec3 lm) {
	float L = lum(base);
	vec3 amb = mix(base, tint_keep_L(ambient_tint.rgb, L), palette_mix);
	vec3 shd = mix(base, tint_keep_L(shadow_tint.rgb, L), shadow_hue) * shadow_depth;
	float lp = max(lm.r, max(lm.g, lm.b));
	float lit = smoothstep(light_threshold, light_threshold + 0.05, lp) * lw;
	vec3 lh = lm / max(lp, 0.0001);
	if (zone >= 0.45 && zone < 0.55) {
		if (!paint_eyes) {
			return amb;
		}
		vec3 e = eye_color.rgb * (L / max(lum(eye_color.rgb), 0.05)) * 1.35;
		return clamp(e, 0.0, 1.0);
	}
	vec3 c;
	if (zone < 0.17) {
		c = shd;
	} else if (zone < 0.45) {
		c = amb;
	} else if (zone < 0.83) {
		c = mix(amb, lit_color(base, L, lh), lit);
	} else {
		// 그림자 쪽 가장자리: 빛 지도 모드에선 그림자면, 2D 배경 모드에선 반대편 조명색 림
		c = (!use_light_map && use_rim) ? mix(base, accent_color.rgb, accent_mix * lw) : shd;
	}
	if (use_rim && near_zone >= 0.83) {
		c = mix(c, no_burn(lh * 1.2), near_rim_mix * lit);
	}
	return c;
}

void fragment() {
	// Godot 4: fragment 의 COLOR 는 이미 텍스처색 × 정점색(모듈레이트). 다시 텍스처를 곱하면 색이 제곱돼 어두워진다.
	vec4 base = COLOR;
	float L0 = lum(base.rgb);
	float lw = line_weight(TEXTURE, UV, TEXTURE_PIXEL_SIZE, L0) * smoothstep(black_range.x, black_range.y, L0);
	vec3 lm;
	if (use_light_map) {
		lm = texture(light_map, clamp((world_pos - lm_rect.xy) / lm_rect.zw, vec2(0.0), vec2(1.0))).rgb;
	} else {
		lm = key_color.rgb;
	}
	vec2 d = fwidth(UV) * 0.25;
	vec3 o = vec3(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 off = vec2((i % 2 == 0) ? -d.x : d.x, (i < 2) ? -d.y : d.y);
		o += shade(base.rgb, texture(zone_mask, UV + off).r, texture(near_rim_mask, UV + off).r, lw, lm);
	}
	o *= 0.25;
	o = mix(o, flash_color.rgb, flash_color.a);
	if (debug_view == 1) {
		o = base.rgb;
	} else if (debug_view == 2) {
		o = lm;
	}
	COLOR = vec4(o, base.a);
}
