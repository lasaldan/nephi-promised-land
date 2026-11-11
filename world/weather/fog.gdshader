shader_type canvas_item;

// Lumpy fog from a seamless noise texture (world/weather/fog.gd). The sprite's
// texture is the big, slow shape of the banks. A second look at the same
// texture, smaller and drifting on TIME, churns the edges so patches thicken,
// thin and break apart instead of only sliding past. The sprite must have
// texture_repeat on so that second look wraps.
//
// Not unshaded on purpose: the DayNight CanvasModulate dims it to a blue-grey
// at night, and a campfire's PointLight2D makes the fog around it glow.

uniform vec4 fog_color : source_color = vec4(0.92, 0.94, 0.97, 1.0);
// 0 is no fog, 1 is as thick as this layer gets.
uniform float density : hint_range(0.0, 1.0) = 1.0;
// Noise below this is clear air. Higher leaves smaller, separate patches.
uniform float threshold : hint_range(0.0, 1.0) = 0.42;
// How far past threshold the fog takes to go solid. Higher is softer edges.
uniform float softness : hint_range(0.01, 1.0) = 0.35;
// How fast the edges churn, in textures per second.
uniform vec2 churn = vec2(0.012, -0.008);
// So two layers sharing the texture don't breathe in step.
uniform float phase = 0.0;
// So two layers sharing the texture don't show the same banks: one reads it
// turned on its side, and shifted (in textures, wrapping).
uniform bool swap_axes = false;
uniform vec2 offset = vec2(0.0);

void fragment() {
	vec2 uv = (swap_axes ? UV.yx : UV) + offset;
	float shape = texture(TEXTURE, uv).r;
	// A whole number of repeats (2x) so this still tiles with the layer.
	float detail = texture(TEXTURE, uv * 2.0 + TIME * churn).r;
	float n = mix(shape, detail, 0.35);
	// The banks slowly swell and shrink.
	float breathe = sin(TIME * 0.11 + phase) * 0.04;
	float amount = smoothstep(threshold + breathe, threshold + breathe + softness, n);
	COLOR = vec4(fog_color.rgb, fog_color.a * amount * density);
}
