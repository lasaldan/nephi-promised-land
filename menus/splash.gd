extends Control

# Studio card shown when the game starts: fades in, holds, fades to black, then
# opens the main menu, which fades up from black. Any click, touch or key skips.

const NEXT_SCENE := "res://menus/main_menu.tscn"
const FADE_TIME := 1.0
const HOLD_TIME := 2.0

var _tween: Tween
var _leaving := false

func _ready() -> void:
	GameSettings.ensure_loaded()
	# Starts with the card and carries on into the menu.
	MenuMusic.start(get_tree())
	$Content.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_interval(0.3)
	_tween.tween_property($Content, "modulate:a", 1.0, FADE_TIME)
	_tween.tween_interval(HOLD_TIME)
	_tween.tween_property($Content, "modulate:a", 0.0, FADE_TIME)
	_tween.tween_callback(_go_to_menu)

func _input(event: InputEvent) -> void:
	var skip := (event is InputEventMouseButton or event is InputEventKey \
			or event is InputEventScreenTouch) and event.is_pressed()
	if not skip or _leaving:
		return
	get_viewport().set_input_as_handled()
	_leaving = true
	_tween.kill()
	_tween = create_tween()
	_tween.tween_property($Content, "modulate:a", 0.0, FADE_TIME * $Content.modulate.a * 0.5)
	_tween.tween_callback(_go_to_menu)

func _go_to_menu() -> void:
	_leaving = true
	get_tree().change_scene_to_file(NEXT_SCENE)
