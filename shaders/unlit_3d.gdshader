// 얼굴 데칼/UI 마커용: 조명 무시, 알파 투명
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque, blend_mix;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float dim = 0.9;
void fragment() {
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb * dim;
	ALPHA = c.a;
}
