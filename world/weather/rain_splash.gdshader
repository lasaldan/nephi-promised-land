shader_type canvas_item;

// Little rings where drops hit the ground (world/weather/rain.gd). There is
// no splash texture: the sprite is a 1 px white texture stretched over the
// whole tile, so UV counts world pixels. The tile is cut into cells; in each
// cell a ring now and then opens and fades at a random spot, and the next one
// lands somewhere else. Every cell runs its own clock, so they never pulse in
// step. The pattern repeats every `cells` cells, which is the layer's
// repeat_size, so it wraps with the layer.
//
// With use_mask on (Rain.splash_surfaces set), each surface layer has its
// own sprite over its tiles, and surface_mask says which of its pixels are
// tile (white) or not (black). A ring needs its middle on a surface, and is
// cut off where the surface ends, so drops landing near a wall don't run up it.

uniform vec4 splash_color : source_color = vec4(0.82, 0.88, 0.97, 0.6);
// Share of cells with a splash in each round. 0 is none.
uniform float amount : hint_range(0.0, 1.0) = 0.3;
// World px per cell. About the spacing of splashes at full rain.
uniform float cell = 16.0;
// Cells across the tile, so the pattern repeats with it.
uniform float cells = 34.0;
// Seconds a ring takes to open and fade.
uniform float life = 0.45;
// Widest a ring gets, in px. It is half as tall, lying flat on the ground.
uniform float radius = 3.5;
uniform bool use_mask = false;
uniform sampler2D surface_mask : filter_nearest, repeat_disable, hint_default_white;
// World px the mask covers: the sprite's whole size.
uniform vec2 mask_size = vec2(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float on_surface(vec2 p) {
	return use_mask ? texture(surface_mask, p / mask_size).r : 1.0;
}

void fragment() {
	// Whole pixels, so rings come out as crisp pixel art.
	vec2 px = floor(UV) + 0.5;
	vec2 home = floor(px / cell);
	vec2 c = mod(home, cells);
	float t = TIME / life + hash(c) * 7.0;
	float age = fract(t);
	// Kept small so the hash stays exact on mobile GPUs.
	float round_ = mod(floor(t), 61.0);
	vec2 seed = c + round_ * vec2(13.7, 7.3);
	float alpha = 0.0;
	if (hash(seed + 0.5) < amount) {
		// Somewhere in the middle of the cell, so rings don't cross into the next.
		vec2 spot = vec2(hash(seed + 1.3), hash(seed + 2.9));
		vec2 centre = floor((home + 0.25 + 0.5 * spot) * cell) + 0.5;
		vec2 d = (px - centre) * vec2(1.0, 2.0);
		float r = mix(0.0, radius, age);
		float ring = step(abs(length(d) - r), 0.6);
		alpha = ring * (1.0 - age) * on_surface(px) * on_surface(centre);
	}
	COLOR = vec4(splash_color.rgb, splash_color.a * alpha);
}
