class_name MenuMusic
extends RefCounted

# The music under the splash card and the main menu. The player sits on the
# tree's root rather than in either scene, so it carries on through the change
# from the splash to the menu. start() fades it up (doing nothing if it is
# already playing), stop() fades it out and frees it. The splash and the menu
# both call start(), so it also returns when the menu is reached again from the
# credits or the pause menu. Leaving the menu for the game or the credits
# stops it.
#
# Static, not an autoload, like GameSettings.

# One of the background tracks from the game (BG_music in world.tscn).
# A path, not a preload, so the class holds no stream once the menu is left
# (a static preload is reported as still in use at exit).
const TRACK := "res://audio/music/gentle_historical_journey.mp3"
const FADE_IN_SECONDS := 2.0

static var _player: AudioStreamPlayer
static var _fade: Tween

static func start(tree: SceneTree) -> void:
	if is_instance_valid(_player):
		return
	GameSettings.ensure_loaded()
	_player = AudioStreamPlayer.new()
	_player.name = "MenuMusic"
	_player.stream = load(TRACK)
	_player.bus = GameSettings.MUSIC
	_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = -80.0
	# The track doesn't loop on its own.
	_player.finished.connect(_player.play)
	# Plays once it is in the tree. Deferred, because start() is called from
	# a scene's _ready, while the root is still busy adding that scene.
	_player.autoplay = true
	tree.root.add_child.call_deferred(_player)
	_fade = tree.create_tween().bind_node(_player)
	_fade.tween_method(_set_level.bind(_player), 0.0, 1.0, FADE_IN_SECONDS)

static func stop(seconds: float) -> void:
	if not is_instance_valid(_player):
		return
	var player := _player
	_player = null
	if _fade:
		_fade.kill()
	# Not get_tree(): stopped straight after start(), it may not be in the tree yet.
	_fade = (Engine.get_main_loop() as SceneTree).create_tween().bind_node(player)
	_fade.tween_method(_set_level.bind(player), db_to_linear(player.volume_db), 0.0, seconds)
	_fade.tween_callback(player.queue_free)

static func _set_level(level: float, player: AudioStreamPlayer) -> void:
	# linear_to_db(0) is -inf.
	player.volume_db = maxf(linear_to_db(level), -80.0)
