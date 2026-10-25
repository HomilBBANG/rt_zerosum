// 역면(inverted hull) 외곽선. mode 0: 법선 방향 확장(둥근 메시), 1: 원점 기준 스케일(박스/원기둥)
shader_type spatial;
render_mode cull_front, unshaded, depth_draw_opaque;
uniform float width = 0.018;
uniform int mode = 0;
uniform vec4 color : source_color = vec4(0.09, 0.07, 0.1, 1.0);
void vertex() {
	if (mode == 0) {
		VERTEX += NORMAL * width;
	} else {
		VERTEX += normalize(VERTEX) * width * 1.4;
	}
}
void fragment() {
	ALBEDO = color.rgb;
}
