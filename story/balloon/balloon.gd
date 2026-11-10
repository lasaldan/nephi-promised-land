extends CanvasLayer
## A basic dialogue balloon for use with Dialogue Manager.

## The action to use for advancing the dialogue
@export var next_action: StringName = &"ui_accept"

## The action to use to skip typing the dialogue
@export var skip_action: StringName = &"ui_cancel"

## The dialogue resource
var resource: DialogueResource

## Temporary game states
var temporary_game_states: Array = []

## See if we are waiting for the player
var is_waiting_for_input: bool = false

## See if we are running a long mutation and should hide the balloon
var will_hide_balloon: bool = false

## A dictionary to store any ephemeral variables
var locals: Dictionary = {}

var _locale: String = TranslationServer.get_locale()

## The current line
var dialogue_line: DialogueLine:
	set(value):
		if value:
			dialogue_line = value
			apply_dialogue_line()
		elif fade_out_seconds > 0.0:
			# The dialogue has finished, so fade the balloon out and close it
			var tween := create_tween()
			tween.tween_property(balloon, "modulate:a", 0.0, fade_out_seconds)
			tween.finished.connect(queue_free)
		else:
			# The dialogue has finished so close the balloon
			queue_free()
	get:
		return dialogue_line

## Seconds the balloon fades out over once the dialogue finishes. At 0 it
## closes at once.
var fade_out_seconds: float = 0.0

## A cooldown timer for delaying the balloon hide when encountering a mutation.
var mutation_cooldown: Timer = Timer.new()

## Plays the voice clip for each line, from res://voice/<character>/<ID>.mp3
## in English and res://voice/<language>/<character>/<ID>.mp3 in another
## (Language.voice_path, made by tools/voice/generate.py). Lines without a
## clip in the current language stay silent.
var voice_player: AudioStreamPlayer = AudioStreamPlayer.new()

## The base balloon anchor
@onready var balloon: Control = %Balloon

## The portrait
@onready var portrait: Control = %SpeakerPortrait

## The label showing the name of the currently speaking character
@onready var character_label: RichTextLabel = %CharacterLabel

## The label showing the currently spoken dialogue
@onready var dialogue_label: DialogueLabel = %DialogueLabel

## The menu of responses
@onready var responses_menu: DialogueResponsesMenu = %ResponsesMenu


func _ready() -> void:
	balloon.hide()
	Engine.get_singleton("DialogueManager").mutated.connect(_on_mutated)

	# If the responses menu doesn't have a next action set, use this one
	if responses_menu.next_action.is_empty():
		responses_menu.next_action = next_action

	mutation_cooldown.timeout.connect(_on_mutation_cooldown_timeout)
	add_child(mutation_cooldown)

	voice_player.bus = GameSettings.VOICE
	voice_player.add_to_group(GameSettings.VOICE_PLAYERS)
	add_child(voice_player)


func _unhandled_input(_event: InputEvent) -> void:
	# Only the balloon is allowed to handle input while it's showing
	get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	## Detect a change of locale and update the current dialogue line to show the new language
	if what == NOTIFICATION_TRANSLATION_CHANGED and _locale != TranslationServer.get_locale() and is_instance_valid(dialogue_label):
		_locale = TranslationServer.get_locale()
		var visible_ratio = dialogue_label.visible_ratio
		self.dialogue_line = await resource.get_next_dialogue_line(dialogue_line.id)
		if visible_ratio < 1:
			dialogue_label.skip_typing()


func _display_name(character: String) -> String:
	if Artifacts.has(character):
		return Artifacts.display_name(character)
	return Cast.display_name(character)


## How big an artifact's picture is drawn beside its lines. Its bottom sits
## where a speaker's feet do, and it stands about as tall as one.
const ARTIFACT_PORTRAIT_SCALE := 1.25
const ARTIFACT_PORTRAIT_FLOOR := Vector2(18, 40)

## An artifact speaks for itself (story/artifacts.gd): its picture stands in
## for a speaker, and its lines are in Nephi's voice.
func _show_artifact_portrait(id: String) -> void:
	for child in portrait.get_children():
		child.visible = false
		child.queue_free()
	var texture := Artifacts.portrait(id)
	if texture == null:
		portrait.visible = false
		return
	var picture := Sprite2D.new()
	picture.texture = texture
	picture.scale = Vector2.ONE * ARTIFACT_PORTRAIT_SCALE
	picture.position = ARTIFACT_PORTRAIT_FLOOR - Vector2(0, texture.get_height() * ARTIFACT_PORTRAIT_SCALE / 2)
	portrait.visible = true
	portrait.add_child(picture)


## Start some dialogue
func start(dialogue_resource: DialogueResource, title: String, extra_game_states: Array = []) -> void:
	temporary_game_states = [self] + extra_game_states
	is_waiting_for_input = false
	resource = dialogue_resource
	self.dialogue_line = await resource.get_next_dialogue_line(title, temporary_game_states)


## Apply any changes to the balloon given a new [DialogueLine].
func apply_dialogue_line() -> void:
	mutation_cooldown.stop()

	is_waiting_for_input = false
	balloon.focus_mode = Control.FOCUS_ALL
	balloon.grab_focus()

	character_label.visible = not dialogue_line.character.is_empty()
	character_label.text = tr(_display_name(dialogue_line.character), "dialogue")

	var speaker: Node2D = null
	if Artifacts.has(dialogue_line.character):
		_show_artifact_portrait(dialogue_line.character)
	elif(dialogue_line.character):
		for child in portrait.get_children():
			child.visible = false
			child.queue_free()
		var path := Cast.scene_path(dialogue_line.character)
		if not path.is_empty():
			speaker = load(path).instantiate()
	if speaker:
		# Not one of the people in the world: no talking to it, no habits.
		speaker.set_meta("portrait", true)
		speaker.scale = Vector2(1.75, 1.75)
		speaker.immovable = true
		speaker.position.y += 40
		speaker.position.x += 16
		portrait.visible = true
		portrait.add_child(speaker)
	elif not Artifacts.has(dialogue_line.character):
		portrait.visible = false

	dialogue_label.hide()
	dialogue_label.dialogue_line = dialogue_line

	responses_menu.hide()
	responses_menu.responses = dialogue_line.responses

	# Show our balloon
	balloon.show()
	will_hide_balloon = false

	_play_voice()

	dialogue_label.show()
	if not dialogue_line.text.is_empty():
		dialogue_label.type_out()
		await dialogue_label.finished_typing

	# Wait for input
	if dialogue_line.responses.size() > 0:
		balloon.focus_mode = Control.FOCUS_NONE
		responses_menu.show()
	elif dialogue_line.time != "":
		var time = dialogue_line.text.length() * 0.02 if dialogue_line.time == "auto" else dialogue_line.time.to_float()
		await get_tree().create_timer(time, false).timeout
		next(dialogue_line.next_id)
	else:
		is_waiting_for_input = true
		balloon.focus_mode = Control.FOCUS_ALL
		balloon.grab_focus()


## Starts this line's voice clip, cutting off the last one. A line with a
## {{variable}} has a clip per value, <ID>__<value>.mp3, so the values passed
## to talk() (such as {"fruit": "apples"}) are tried first.
func _play_voice() -> void:
	voice_player.stop()
	var key := dialogue_line.translation_key
	if dialogue_line.character.is_empty() or key.is_empty() or key.contains(" "):
		return
	var clips: Array[String] = []
	for state in temporary_game_states:
		if state is Dictionary:
			for value in state.values():
				if value is String:
					clips.append("%s__%s" % [key, value])
	clips.append(key)
	for clip in clips:
		var stream := Language.voice(dialogue_line.character, clip)
		if stream:
			voice_player.stream = stream
			voice_player.play()
			return


## Go to the next line
func next(next_id: String) -> void:
	self.dialogue_line = await resource.get_next_dialogue_line(next_id, temporary_game_states)


#region Signals


func _on_mutation_cooldown_timeout() -> void:
	if will_hide_balloon:
		will_hide_balloon = false
		balloon.hide()


func _on_mutated(_mutation: Dictionary) -> void:
	is_waiting_for_input = false
	will_hide_balloon = true
	mutation_cooldown.start(0.1)


func _on_balloon_gui_input(event: InputEvent) -> void:
	# See if we need to skip typing of the dialogue
	if dialogue_label.is_typing:
		var mouse_was_clicked: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
		var skip_button_was_pressed: bool = event.is_action_pressed(skip_action)
		if mouse_was_clicked or skip_button_was_pressed:
			get_viewport().set_input_as_handled()
			dialogue_label.skip_typing()
			return

	if not is_waiting_for_input: return
	if dialogue_line.responses.size() > 0: return

	# When there are no response options the balloon itself is the clickable thing
	get_viewport().set_input_as_handled()

	if event is InputEventMouseButton and event.is_pressed() and event.button_index == MOUSE_BUTTON_LEFT:
		next(dialogue_line.next_id)
	elif event.is_action_pressed(next_action) and get_viewport().gui_get_focus_owner() == balloon:
		next(dialogue_line.next_id)


func _on_responses_menu_response_selected(response: DialogueResponse) -> void:
	next(response.next_id)


#endregion
