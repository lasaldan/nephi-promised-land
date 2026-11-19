shader_type canvas_item;
// Dust motes in the light through a deck grate (world/props/grate_light.gd).
// Each mote shows only as brightly as the beam texture is where it floats,
// tinted with the light, so it glints crossing a square and is gone in the
// bars' shadow. The particles use local coords, so VERTEX is in the
// GrateLight's own space, whose origin is the middle of the beams.
render_mode unshaded, blend_add;

uniform sampler2D beams : filter_nearest;
uniform vec4 light_color : source_color = vec4(1.0);
uniform float energy = 1.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec2 size = vec2(textureSize(beams, 0));
	float lit = texture(beams, local / size + 0.5).r;
	COLOR = vec4(light_color.rgb * energy * lit, COLOR.a);
}
