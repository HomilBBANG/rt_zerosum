// CanvasGroup 용 외곽선: 파츠·무기가 합쳐진 실루엣 둘레에만 선을 긋는다 (관절 이음새에는 선이 생기지 않음).
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float thickness : hint_range(0.0, 10.0) = 3.0;   // 화면 픽셀
uniform vec4 line_color : source_color = vec4(0.06, 0.04, 0.07, 1.0);

void fragment() {
	vec4 c = textureLod(screen_texture, SCREEN_UV, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;   // CanvasGroup 버퍼는 premultiplied
	}
	vec2 px = SCREEN_PIXEL_SIZE * thickness;
	float a = 0.0;
	for (int i = 0; i < 12; i++) {
		float ang = 6.2831853 * float(i) / 12.0;
		a = max(a, textureLod(screen_texture, SCREEN_UV + vec2(cos(ang), sin(ang)) * px, 0.0).a);
	}
	vec4 outline = vec4(line_color.rgb, a * line_color.a);
	COLOR = mix(outline, vec4(c.rgb, 1.0), c.a);
	COLOR.a = max(c.a, outline.a);
}
