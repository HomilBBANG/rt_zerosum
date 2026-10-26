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
// false: 조명 마스크가 없는 프레임 (사용자가 막 넣은 애니메이션 등) → 주변광 + 약한 주조명을 고르게 섞음. tools/char_sprites.py masks 로 마스크를 만들면 true
uniform bool use_zone_mask = true;
// 선화 마스크 (tools/char_sprites.py lines): 1 = 선 → 조명 없이 원화 색 그대로 (선화 유지, 면에만 조명)
uniform sampler2D line_mask : filter_linear, repeat_disable;
uniform bool use_line_mask = false;
uniform float line_keep : hint_range(0.0, 1.0) = 1.0;
// 눈 마스크 (tools/char_sprites.py eyes): 1 = 흰자·눈동자 → 조명·네온 없이 원화 색 그대로
uniform sampler2D eye_mask : filter_linear, repeat_disable;
uniform bool use_eye_mask = false;
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
// 외곽 림 (빛 반대쪽 가장자리 선): 마스크의 림 구역 대신 그림 실루엣(알파)을 빛 방향으로 밀어 그 차이만큼 칠함
// → 실루엣 윤곽을 그대로 따라가 계단 없이 매끄럽고, 다리 사이 같은 안쪽 가장자리에도 생김. 두께 = rim_px (원화 px)
uniform bool rim_from_alpha = true;
uniform bool light_from_right = true;   // 텍스처 기준 빛 방향 (스크립트가 넣음)
uniform float rim_px : hint_range(0.0, 60.0) = 14.0;
uniform float neon_rim : hint_range(0.0, 1.0) = 0.92;   // 네온 칠일 때 림 세기 (accent_mix 보다 크면 이것)
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform int debug_view = 0;   // 1: 원화 그대로 출력 (디버그)

// ── 네온 칠 (character.json "style": "neon") ── 레퍼런스: 면은 조명색으로 쨍하게 덮고 선화만 원화 그대로.
//   원화 밝기 → 조명색 명도로 옮김 (검정 옷도 바닥 밝기 neon_floor 로 들어 올려 깊은 조명색이 됨, 흰 옷은 밝은 조명색)
//   원화 고유색은 neon_keep 만큼만 남김 (빨간 머리·적십자가 '조명 받은 빨강'으로 읽히게)
uniform float neon : hint_range(0.0, 1.0) = 1.0;          // 0 = 기존 칠, 1 = 네온 칠 (기본)
uniform float neon_floor : hint_range(0.0, 0.5) = 0.19;    // 가장 어두운 면의 밝기 (선화는 이보다 어두워서 묻히지 않음)
uniform float neon_keep : hint_range(0.0, 1.0) = 0.45;     // 원화 고유색(채도) 남기는 양
uniform float neon_white : hint_range(0.0, 1.0) = 0.38;    // 밝은 면을 흰빛 쪽으로 (흰 코트가 '빛나는 흰색'으로 남게)
uniform float neon_shadow : hint_range(0.2, 1.0) = 0.70;   // 그림자 면 밝기 배율
uniform float neon_dark : hint_range(0.0, 0.5) = 0.30;     // 검정·어두운 면을 푸른 보라 쪽으로 돌리는 양 (0 = 조명색 그대로 어둡게 → 갈색·고동색)
uniform float neon_cool : hint_range(0.0, 0.4) = 0.16;     // 그림자 면 색상을 주조명색에서 푸른 보라(0.72) 쪽으로 돌리는 양 — 빛/그림자가 색상으로도 갈림
// 그라데이션: 몸 위(빛 쪽)→아래(반대쪽)로 주조명색 색상을 푸른 보라 쪽으로 돌림 (핑크→보라, 초록→청록, 빨강→마젠타)
uniform float neon_gradient : hint_range(0.0, 1.0) = 0.0;
uniform float grad_hue : hint_range(0.0, 0.4) = 0.16;      // 그라데이션 끝에서 돌아가는 색상 양 (0.16 ≈ 58°)
uniform vec2 grad_dir = vec2(-0.35, 1.0);                  // 텍스처 UV 기준 진행 방향 (x 는 빛 방향에 따라 스크립트가 뒤집음)

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

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * clamp(p - 1.0, 0.0, 1.0);
}

// 색상환에서 가까운 쪽으로 a → b (보색끼리 RGB 로 섞으면 회색이 되므로)
vec3 hue_lerp(vec3 a, vec3 b, float t) {
	vec3 ha = rgb2hsv(a);
	vec3 hb = rgb2hsv(b);
	float dh = hb.x - ha.x;
	dh -= round(dh);
	return hsv2rgb(vec3(fract(ha.x + dh * t), mix(ha.y, hb.y, t), mix(ha.z, hb.z, t)));
}

// 색상을 target 색상(0~1) 쪽으로 최대 amt 만큼 돌림 (가까운 방향)
vec3 hue_toward(vec3 c, float target, float amt) {
	vec3 h = rgb2hsv(c);
	float dh = target - h.x;
	dh -= round(dh);
	return hsv2rgb(vec3(fract(h.x + clamp(dh, -amt, amt)), h.y, h.z));
}

// 어두운 면 색상: 주조명색을 푸른 보라(0.72) 쪽으로 neon_dark 만큼 돌린 색
vec3 neon_dark_hue() {
	return hue_toward(key_color.rgb, 0.72, neon_dark);
}

// 네온 칠: src = 원화색, light = 이 면에 닿는 조명색, gain = 면 밝기 배율
// 원화 밝기로 색을 고름 (그라데이션 맵): 어두운 면(검정 옷) → 깊은 보라 neon_dark, 밝은 면 → 조명색. 갈색처럼 탁해지지 않게
vec3 neon_fill(vec3 src, vec3 light, float gain) {
	float L = lum(src);
	float v = mix(neon_floor, 1.0, L) * gain;
	vec3 hue = hue_of(hue_lerp(hue_of(neon_dark_hue()), hue_of(light), smoothstep(0.06, 0.45, L)));
	vec3 c = hue * v;
	c += (src - vec3(L)) * neon_keep;                          // 원화 고유색 조금
	c = mix(c, vec3(v), smoothstep(0.55, 1.0, L) * neon_white); // 밝은 면은 흰빛 섞인 조명색
	return clamp(c, 0.0, 1.0);
}

vec3 shade_neon(vec3 src, float zone, float gt) {
	vec3 key = hue_toward(key_color.rgb, 0.72, grad_hue * gt * neon_gradient);
	vec3 sh = mix(hue_toward(key, 0.72, neon_cool), hue_of(shadow_tint.rgb), 0.25);
	if (zone < 0.17 || (zone >= 0.83 && !use_rim)) {
		return neon_fill(src, sh, neon_shadow);
	} else if (zone < 0.45) {
		return neon_fill(src, hue_lerp(ambient_tint.rgb, key, 0.45), 0.88);
	} else if (zone < 0.55) {
		vec3 e = (paint_eyes ? eye_color.rgb : key) * (lum(src) / max(lum(paint_eyes ? eye_color.rgb : key), 0.05)) * 1.35;
		return clamp(mix(e, neon_fill(src, key, 1.0), paint_eyes ? 0.2 : 0.7), 0.0, 1.0);
	} else if (zone < 0.83) {
		return neon_fill(src, key, 1.08);
	}
	return mix(neon_fill(src, key, 1.08), accent_color.rgb, accent_mix);
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

// 기존 칠(base = 두 번 곱한 진한 톤)과 네온 칠(src = 원화색)을 neon 으로 섞음
vec3 shade_any(vec3 base, vec3 src, float zone, float gt) {
	if (neon <= 0.0) {
		return shade(base, zone);
	}
	return mix(shade(base, zone), shade_neon(src, zone, gt), neon);
}

vec3 shade2(vec3 base, vec3 src, vec2 uv, float gt) {
	if (!use_zone_mask) {
		return mix(shade_any(base, src, 0.33, gt), shade_any(base, src, 0.7, gt), 0.35);
	}
	float z = texture(zone_mask, uv).r;
	if (rim_from_alpha && z >= 0.83) {
		z = 0.0;   // 마스크 림 구역은 그림자 면으로 (림은 edge_rim 이 그림)
	}
	vec3 c = shade_any(base, src, z, gt);
	if (!rim_from_alpha && use_near_rim && texture(near_rim_mask, uv).r >= 0.83) {
		c = mix(c, near_rim_color.rgb, near_rim_mix);
	}
	return c;
}

vec2 rot(vec2 v, float a) {
	return vec2(v.x * cos(a) - v.y * sin(a), v.x * sin(a) + v.y * cos(a));
}

// 실루엣 가장자리 띠: 빛 반대쪽으로 옮긴 원판 안의 '그림 밖' 비율 (12점 나선 표본 = 흐린 실루엣) → 문턱값으로 띠.
// 원판(중심 rim_px*0.55, 반지름 rim_px*0.55)이 아래쪽 바깥도 조금 보므로 머리카락 끝처럼 날카로운 끝까지 채움.
// 표본을 원판에 흩어 평균하므로 띠 안쪽 경계가 실루엣을 부드럽게 따라감 (계단 없음)
float edge_rim(sampler2D tex, vec2 uv, vec2 dir, vec2 px) {
	float q = rim_px * 0.55;
	vec2 c = uv + dir * q * px;
	float out_a = 0.0;
	for (int i = 0; i < 12; i++) {
		float fi = float(i) + 0.5;
		float rr = q * sqrt(fi / 12.0);
		float an = fi * 2.39996;
		out_a += 1.0 - texture(tex, c + vec2(cos(an), sin(an)) * rr * px).a;
	}
	out_a /= 12.0;
	// 바깥이 정말 트인 곳인지: 같은 방향으로 더 멀리(1.8·2.6·3.4배)도 비어 있어야 함
	// → 그림 안쪽의 작은 틈(턱 아래, 목 옆, 코트 밑단과 부츠 사이)에는 림이 생기지 않음
	float open_a = 0.0;
	for (int k = 0; k < 3; k++) {
		open_a += 1.0 - texture(tex, uv + dir * rim_px * (1.8 + 0.8 * float(k)) * px).a;
	}
	return smoothstep(0.10, 0.30, out_a) * smoothstep(0.55, 0.95, open_a / 3.0);
}

void fragment() {
	// 텍스처색 × COLOR(이미 텍스처색 × 모듈레이트) = 원화색을 두 번 곱한 진한 톤 (확정된 룩)
	vec3 orig = COLOR.rgb;   // 원화 색 (텍스처 × 모듈레이트 한 번) — 선화는 이 색 그대로
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 d = fwidth(UV) * 0.25;
	vec2 gd = normalize(grad_dir);
	float gt = smoothstep(0.0, 1.0, clamp(dot(UV - 0.5, gd) / (abs(gd.x) * 0.5 + abs(gd.y) * 0.5) * 0.5 + 0.5, 0.0, 1.0));
	vec3 o = shade2(base.rgb, orig, UV + vec2(-d.x, -d.y), gt)
		+ shade2(base.rgb, orig, UV + vec2(d.x, -d.y), gt)
		+ shade2(base.rgb, orig, UV + vec2(-d.x, d.y), gt)
		+ shade2(base.rgb, orig, UV + vec2(d.x, d.y), gt);
	o *= 0.25;
	float l = lum(o);
	o = clamp(mix(vec3(l), o, saturation), 0.0, 1.0);
	float rim_v = 0.0;   // 림 세기 (림 띠 안에서는 진짜 먹선만 보존 — 가는 머리카락 끝 같은 색 획은 림으로 채움)
	if (rim_from_alpha) {
		vec2 away = normalize(vec2(light_from_right ? -1.0 : 1.0, -0.25));   // 빛 반대쪽 (살짝 위 — 어깨·모자 윗선도)
		if (use_rim) {
			float rv = edge_rim(TEXTURE, UV, away, TEXTURE_PIXEL_SIZE) * max(accent_mix, neon_rim * neon);
			o = mix(o, accent_color.rgb, rv);
			rim_v = rv;
		}
		if (use_near_rim) {
			o = mix(o, near_rim_color.rgb, edge_rim(TEXTURE, UV, vec2(-away.x, away.y), TEXTURE_PIXEL_SIZE) * near_rim_mix);
		}
	}
	if (use_eye_mask) {
		o = mix(o, orig, texture(eye_mask, UV).r);
	}
	if (use_line_mask) {
		float lw = texture(line_mask, UV).r * line_keep;
		lw *= mix(1.0, smoothstep(0.32, 0.14, lum(orig)), rim_v);   // 림 띠 안: 어두운 먹선만 (빨간 머리카락 끝 같은 색 획은 림)
		o = mix(o, min(o, orig), lw);   // 어두운 선은 원화 그대로, 선 옆 밝은 테두리는 조명 받은 색 유지
	}
	o = mix(o, flash_color.rgb, flash_color.a);
	if (debug_view == 1) {
		o = base.rgb;
	}
	COLOR = vec4(o, base.a);
}
