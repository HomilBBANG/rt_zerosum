// Godot 4.7 spatial cel shader — 2D cel_zoned_lighting 과 같은 4구역 규칙을 실광원으로 재현.
//  빛이 전혀 닿지 않음(차폐)          = 그림자 구역
//  약한 채움광(에너지 < 0.6)이 닿음     = 주변광 구역
//  강한 색광원(키/보조)이 닿음         = 키/보조광 구역 (하드 에지)
// palette_paint = true (배경 방): 구역마다 '장면 팔레트 색상'으로 확실하게 칠한다 — 재질 색은 밝기(명도)만 쓴다.
//   그림자 = 그림자 색상, 주변광 = 주변광 색상, 빛 = 광원 색상 그대로 (회색 재질 × 색조로 탁해지지 않게)
// palette_paint = false (3D 캐릭터 모드): 재질 색 × 색조 (예전 방식)
//
// 호환성 렌더러는 스폿광을 '가산 패스'로 따로 그려 음수 기여가 잘린다 → 빛 구역에서 주변광 색을 빼지 못해
// 광원색이 주변광과 섞여 탁해진다(핑크+청록=옅은 분홍). 그래서 palette_paint 에선
//   기본 패스: 스폿이 닿는 영역(원뿔 + 문/창 개구부 + 면 방향, 해석적 계산)은 주변광 대신 그림자 색
//   스폿 패스: 같은 영역 안에서 실제로 빛이 닿는 곳(그림자맵 통과)에만 광원색 - 그림자색 을 더함
// → 빛 받는 곳 = 광원색 그대로, 빛 영역 안의 그림자(캐릭터·소품·문짝) = 짙은 그림자색 (레퍼런스처럼)
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
uniform bool palette_paint = false;
// 스폿 2개(0 = 문 키, 1 = 창 보조)의 해석적 영역: 위치, 방향(정규화), cos(반각), 개구부(벽 z 평면의 x,y,w,h)
uniform vec3 spot_pos_0 = vec3(0.0);
uniform vec3 spot_dir_0 = vec3(0.0, -1.0, 0.0);
uniform float spot_cos_0 = 2.0;
uniform vec4 spot_rect_0 = vec4(0.0);
uniform vec3 spot_pos_1 = vec3(0.0);
uniform vec3 spot_dir_1 = vec3(0.0, -1.0, 0.0);
uniform float spot_cos_1 = 2.0;
uniform vec4 spot_rect_1 = vec4(0.0);
uniform float wall_z = -3.4;

varying vec3 v_base;
varying vec3 v_world;
varying vec3 v_wnormal;
varying float v_spot0;
varying float v_spot1;

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// 팔레트 칠: 재질 밝기 v 로 같은 색상의 밝고 어두움만 나눈다
vec3 pal_shadow(vec3 base) {
	return shadow_tint.rgb * (0.55 + 0.8 * lum(base));
}

vec3 pal_ambient(vec3 base) {
	return ambient_tint.rgb * (0.35 + 0.8 * lum(base));
}

vec3 pal_light(vec3 lcol, vec3 base) {
	vec3 c = lcol * (0.88 + 0.3 * lum(base));
	return c / max(1.0, max(c.r, max(c.g, c.b)));
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// 월드 점 q 가 스폿의 원뿔 안 + 벽 개구부를 통과 + 면이 광원을 향함 → 1
float spot_region(vec3 q, vec3 n, vec3 lp, vec3 ld, float lcos, vec4 rect) {
	vec3 to = q - lp;
	float dist = length(to);
	if (dist < 0.001) {
		return 0.0;
	}
	vec3 dir = to / dist;
	if (dot(dir, ld) <= lcos || dot(n, -dir) <= 0.0) {
		return 0.0;
	}
	if (rect.z > 0.0 && abs(q.z - lp.z) > 0.001) {
		float t = (wall_z - lp.z) / (q.z - lp.z);
		if (t > 0.0 && t < 1.0) {
			vec2 hit = (lp + to * t).xy;
			// 개구부를 2cm 넓혀 판정: 경계가 어긋나면 옅은 띠 대신 짙은 선이 되도록
			if (hit.x < rect.x - 0.02 || hit.x > rect.x + rect.z + 0.02 || hit.y < rect.y - 0.02 || hit.y > rect.y + rect.w + 0.02) {
				return 0.0;
			}
		}
	}
	return 1.0;
}

void fragment() {
	vec3 base = albedo.rgb;
	if (use_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	v_base = base;
	v_spot0 = 0.0;
	v_spot1 = 0.0;
	if (palette_paint) {
		v_spot0 = spot_region(v_world, v_wnormal, spot_pos_0, spot_dir_0, spot_cos_0, spot_rect_0);
		v_spot1 = spot_region(v_world, v_wnormal, spot_pos_1, spot_dir_1, spot_cos_1, spot_rect_1);
		// 최종색을 DIFFUSE_LIGHT 에 그대로 쌓기 위해 ALBEDO = 1
		ALBEDO = vec3(1.0);
		EMISSION = mix(pal_shadow(base), flash_color.rgb, flash);
	} else {
		ALBEDO = base;
		EMISSION = mix(base * shadow_tint.rgb, flash_color.rgb, flash);
	}
}

void light() {
	float peak = max(LIGHT_COLOR.r, max(LIGHT_COLOR.g, LIGHT_COLOR.b));
	float strength = peak / 3.14159;
	vec3 lcol = LIGHT_COLOR / max(peak, 0.0001);
	float band = dot(NORMAL, LIGHT) * ATTENUATION;
	vec3 shadow_part;
	vec3 ambient_part;
	if (palette_paint) {
		shadow_part = pal_shadow(v_base);
		ambient_part = pal_ambient(v_base);
	} else {
		shadow_part = ALBEDO * shadow_tint.rgb;
		ambient_part = ALBEDO * ambient_tint.rgb;
	}
	if (strength < 0.6) {
		// 채움광(방향광, 그림자 O): 그림자 구역 → 주변광 구역 (palette_paint: 스폿 영역 안은 그림자색 유지)
		float lit = step(fill_threshold, band);
		if (palette_paint) {
			lit *= 1.0 - max(v_spot0, v_spot1);
		}
		// palette_paint: 렌더러가 방향광 확산에 π 를 곱하므로(실측, 스폿은 아님) 나눠서 팔레트 색 그대로
		DIFFUSE_LIGHT += lit * (ambient_part - shadow_part) / (palette_paint ? PI : 1.0);
	} else if (palette_paint) {
		// 어느 스폿인지: 광원 방향이 스폿 0/1 위치 쪽인지로 판별. 그 스폿 영역 안에서 그림자맵을 통과한 곳만 광원색
		vec3 to0 = normalize((VIEW_MATRIX * vec4(spot_pos_0 - v_world, 0.0)).xyz);
		float region = dot(to0, LIGHT) > 0.999 ? v_spot0 : v_spot1;
		float lit = step(0.0001, ATTENUATION) * step(0.0, dot(NORMAL, LIGHT)) * region;
		DIFFUSE_LIGHT += lit * max(pal_light(lcol, v_base) - shadow_part, vec3(0.0));
	} else {
		// 색광원: 주변광 구역을 '덮어써서' 광원색이 되도록 (주변광 몫을 빼서 가산 누적을 상쇄 — 채도 유지)
		float lit = step(threshold, band * min(strength, 2.0));
		vec3 target = mix(ALBEDO, lcol, light_mix);
		DIFFUSE_LIGHT += lit * (target - ambient_part);
	}
}
