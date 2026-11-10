extends Node

# Fits the game to the window's shape. The project's 512x288 (16 by 9 tiles)
# is the least that is ever shown. A wider window, such as a phone, shows
# more tiles across; a squarer one, such as an iPad, shows more down. Past
# MIN_ASPECT and MAX_ASPECT it stops growing and the stretch aspect ("keep")
# puts black bars on the rest, so a very wide or tall desktop window cannot
# see across the map.
#
# Screen-space UI should anchor to the edges, or lay itself out again on the
# viewport's size_changed, rather than assume 512x288.

const BASE := Vector2(512, 288)
# 16 by 12 tiles.
const MIN_ASPECT := 4.0 / 3.0
# 21 by 9 tiles.
const MAX_ASPECT := 21.0 / 9.0

func _ready() -> void:
	get_tree().root.size_changed.connect(fit)
	fit()

# Runs on its own when the window changes size. Call it after resizing the
# window from code, in case the size it ends up at comes in late.
func fit() -> void:
	var root := get_tree().root
	var window := Vector2(root.size)
	if window.x <= 0 or window.y <= 0:
		return
	var aspect := clampf(window.x / window.y, MIN_ASPECT, MAX_ASPECT)
	var view := BASE
	if aspect > BASE.x / BASE.y:
		view.x = BASE.y * aspect
	else:
		view.y = BASE.x / aspect
	# Even, so the camera's middle lands on a whole pixel.
	var size := Vector2i((view / 2).round() * 2)
	# Setting it emits size_changed again; the check ends that there.
	if root.content_scale_size != size:
		root.content_scale_size = size
