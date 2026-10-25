// CanvasGroup 용 외곽선: 파츠·무기가 합쳐진 실루엣 둘레에만 선을 긋는다 (관절 이음새에는 선이 생기지 않음).
// thickness 는 1280×720 기준 논리 픽셀. 레티나·전체화면에서도 같은 굵기로 보이도록 실제 화면 배율을 곱한다.
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float thickness : hint_range(0.0, 6.0) = 0.45;
uniform vec4 line_color : source_color = vec4(0.06, 0.04, 0.07, 1.0);

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;   // CanvasGroup 버퍼는 premultiplied
	}
	float ui_scale = max(1.0, min(1.0 / (SCREEN_PIXEL_SIZE.x * 1280.0), 1.0 / (SCREEN_PIXEL_SIZE.y * 720.0)));
	vec2 px = SCREEN_PIXEL_SIZE * thickness * ui_scale;
	float a = 0.0;
	for (int i = 0; i < 16; i++) {
		float ang = 6.2831853 * float(i) / 16.0;
		a = max(a, textureLod(screen_texture, SCREEN_UV + vec2(cos(ang), sin(ang)) * px, 0.0).a);
	}
	// 머리카락처럼 가장자리가 반투명한 원화도 외곽선이 흐려지지 않게 커버리지를 끌어올림
	a = smoothstep(0.06, 0.5, a);
	vec4 outline = vec4(line_color.rgb, a * line_color.a);
	COLOR = mix(outline, vec4(c.rgb, 1.0), c.a);
	COLOR.a = max(c.a, outline.a);
}
