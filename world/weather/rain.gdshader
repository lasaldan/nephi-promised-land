shader_type canvas_item;

// Falling rain streaks (world/weather/rain.gd). The texture is a scatter of
// pixel streaks, already slanted with the wind: red is how bright each pixel
// is (faint tail, bright head), green is that streak's rank, 0 to 1. The
// layer's autoscroll does the falling. amount shows only the streaks ranked
// below it, so light rain is a few drops and heavy rain is all of them, with
// no new texture as it builds.
//
// Not unshaded on purpose: the DayNight CanvasModulate dims it at night, and
// a campfire's PointLight2D lights the drops falling near it.

uniform vec4 rain_color : source_color = vec4(0.78, 0.84, 0.95, 0.55);
// 0 is no streaks, 1 is every streak in the texture.
uniform float amount : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	vec4 streak = texture(TEXTURE, UV);
	// A little soft at the cut, so drops fade in as the rain builds instead
	// of popping on.
	float shown = 1.0 - smoothstep(amount - 0.06, amount, streak.g);
	COLOR = vec4(rain_color.rgb, rain_color.a * streak.r * shown);
}
