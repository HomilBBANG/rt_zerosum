// 캐릭터 전용 셀 라이팅 (배경은 cel_zoned_lighting 그대로).
// 배경식 mix(고유색, 광원색) 은 캐릭터의 명암·고유색을 지워 '반투명 막'처럼 보이므로,
// 캐릭터는 고유색 × 광원색(곱하기) + 약한 광원색 가산 + 채도 보정으로 색을 '입힌다'.
// zone_mask: 0 그림자 / 85 주변광 / 128 고유색 유지(눈) / 170 주조명 / 255 림(보조광)
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D zone_mask : filter_nearest, repeat_disable;
uniform vec4 shadow_tint : source_color = vec4(0.06, 0.18, 0.19, 1.0);
uniform vec4 ambient_tint : source_color = vec4(0.42, 0.75, 0.72, 1.0);
uniform vec4 key_color : source_color = vec4(1.0, 0.12, 0.47, 1.0);
uniform vec4 accent_color : source_color = vec4(0.22, 1.0, 0.73, 1.0);
uniform float key_mix : hint_range(0.0, 1.0) = 0.6;      // 주조명 색 입히는 세기
uniform float accent_mix : hint_range(0.0, 1.0) = 0.85;  // 림 세기
uniform float shadow_lift : hint_range(0.0, 1.0) = 0.22; // 그림자에서도 형태가 보이도록 띄우는 양
uniform float saturation : hint_range(0.0, 2.0) = 1.3;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 0.0);

vec3 saturate_rgb(vec3 c, float s) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return clamp(mix(vec3(l), c, s), 0.0, 1.0);
}

// 고유색에 빛 색을 곱해 입힌다. gain 은 빛의 밝기, add 는 어두운 의상에 남는 색 광택
vec3 tinted(vec3 base, vec3 light, float strength, float gain, float add) {
	vec3 filt = mix(vec3(1.0), light, strength);
	return clamp(base * filt * gain + light * add, 0.0, 1.0);
}

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	float zone = texture(zone_mask, UV).r;
	vec3 o;
	if (zone < 0.17) {
		// 그림자: 어둡지만 검정으로 뭉개지지 않게 (그림자색 쪽으로 물든 낮은 명도)
		vec3 sh = shadow_tint.rgb * 2.2 + vec3(shadow_lift);
		o = clamp(base.rgb * sh * 0.75 + shadow_tint.rgb * 0.08, 0.0, 1.0);
	} else if (zone < 0.45) {
		o = tinted(base.rgb, ambient_tint.rgb, 0.55, 1.0, 0.04);
	} else if (zone < 0.55) {
		o = base.rgb;
	} else if (zone < 0.83) {
		o = tinted(base.rgb, key_color.rgb, key_mix, 1.25, 0.10);
	} else {
		o = mix(base.rgb, accent_color.rgb, accent_mix);
	}
	o = saturate_rgb(o, saturation);
	o = mix(o, flash_color.rgb, flash_color.a);
	COLOR = vec4(o, base.a);
}
