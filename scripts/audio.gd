extends Node

signal sfx_played(event: String)

const SOUNDS := {
	"fold": ["kenney_rpg/bookFlip1.ogg", "kenney_rpg/bookFlip2.ogg"],
	"unfold": ["kenney_rpg/bookOpen.ogg"],
	"throw": ["kenney_casino/card-shove-1.ogg"],
	"land": ["kenney_casino/card-place-2.ogg"],
	"recover": ["kenney_casino/cards-pack-take-out-1.ogg"],
	"take": ["kenney_casino/card-slide-2.ogg"],
	"clear": ["kenney_interface/confirmation_001.ogg"],
	"step": ["kenney_impact/footstep_grass_000.ogg", "kenney_impact/footstep_grass_001.ogg"],
	"open": ["kenney_interface/open_001.ogg"],
	"close": ["kenney_interface/close_001.ogg"],
	"gauge": ["kenney_interface/click_001.ogg"],
	"power": ["kenney_interface/select_001.ogg"],
	"impact": ["kenney_interface/tick_001.ogg"],
	"save": ["kenney_interface/confirmation_001.ogg"],
	"error": ["kenney_interface/error_002.ogg"]
}
var music := AudioStreamPlayer.new()
var voices: Array[AudioStreamPlayer] = []
var streams: Dictionary = {}
var variants: Dictionary = {}
var next_voice := 0
var settings := PopupPanel.new()
var volumes: Dictionary = {"Music":0.5, "SFX":0.75}
var muted: Dictionary = {"Music":false, "SFX":false}
var settings_path := "user://audio.cfg"
var closing := false

func _ready() -> void:
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(_close_requested)
	var config := ConfigFile.new()
	config.load(settings_path)
	for bus in volumes:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
		var value: Variant = config.get_value(bus, "volume", volumes[bus])
		if (value is float or value is int) and is_finite(float(value)): volumes[bus] = clampf(float(value), 0, 1)
		muted[bus] = config.get_value(bus, "muted", false) == true
		_apply_bus(bus)
	for event in SOUNDS:
		var clips: Array[AudioStream] = []
		for path in SOUNDS[event]:
			var clip := load("res://assets/audio/" + path) as AudioStream
			if clip != null: clips.append(clip)
		streams[event] = clips
	for i in 8:
		var voice := AudioStreamPlayer.new()
		voice.bus = "SFX"
		add_child(voice)
		voices.append(voice)
	music.bus = "Music"
	music.volume_db = -14
	music.stream = load("res://assets/audio/music/Etirwer_Looped.ogg")
	if music.stream != null: music.stream.loop = true
	add_child(music)
	_build_settings()
	if not OS.has_feature("web"): _start_music()

func _start_music() -> void:
	if AudioServer.get_driver_name() != "Dummy" and music.stream != null and not music.playing: music.play()

func _input(event: InputEvent) -> void:
	if (event is InputEventKey or event is InputEventMouseButton) and event.is_pressed(): _start_music()

func play_sfx(event: String) -> void:
	if not streams.has(event): return
	var clips: Array = streams[event]
	if clips.is_empty(): return
	var variant: int = variants.get(event, 0)
	variants[event] = variant + 1
	var voice := voices[next_voice]
	next_voice = (next_voice + 1) % voices.size()
	voice.stream = clips[variant % clips.size()]
	voice.volume_db = -24 if event == "step" else -10
	if AudioServer.get_driver_name() != "Dummy": voice.play()
	sfx_played.emit(event)

func _exit_tree() -> void:
	music.stop()
	music.stream = null
	for voice in voices:
		voice.stop()
		voice.stream = null
	streams.clear()
	voices.clear()

func stop_all() -> void:
	music.stop()
	for voice in voices: voice.stop()
	# Let the audio thread retire active OGG playbacks before the resource teardown.
	if AudioServer.get_driver_name() != "Dummy": await get_tree().create_timer(0.1).timeout

func _close_requested() -> void:
	if closing: return
	closing = true
	await stop_all()
	get_tree().quit()

func _apply_bus(bus: String) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.0001, volumes[bus])))
	AudioServer.set_bus_mute(index, muted[bus] or volumes[bus] == 0)

func set_volume(bus: String, value: float) -> void:
	if not volumes.has(bus) or not is_finite(value): return
	volumes[bus] = clampf(value, 0, 1)
	_apply_bus(bus)
	_save_settings()

func set_muted(bus: String, value: bool) -> void:
	if not muted.has(bus): return
	muted[bus] = value
	_apply_bus(bus)
	_save_settings()

func _save_settings() -> void:
	var config := ConfigFile.new()
	for bus in volumes:
		config.set_value(bus, "volume", volumes[bus])
		config.set_value(bus, "muted", muted[bus])
	config.save(settings_path)

func add_button(parent: Control) -> Button:
	var button := Button.new()
	button.name = "SoundSettings"
	button.text = "소리"
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(func() -> void:
		if settings.visible: return
		play_sfx("open")
		settings.popup_centered(Vector2i(340, 230))
	)
	parent.add_child(button)
	return button

func _build_settings() -> void:
	add_child(settings)
	settings.exclusive = true
	settings.theme = Theme.new()
	settings.theme.default_font = preload("res://assets/fonts/NanumGothic-Regular.ttf")
	settings.theme.default_font_size = 16
	var style := StyleBoxFlat.new()
	style.bg_color = Color("182a30")
	style.set_content_margin_all(16)
	settings.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	settings.add_child(column)
	var title := Label.new()
	title.text = "소리 설정"
	column.add_child(title)
	for bus in volumes:
		var row := HBoxContainer.new()
		column.add_child(row)
		var label := Label.new()
		label.text = "음악" if bus == "Music" else "효과음"
		label.custom_minimum_size.x = 48
		row.add_child(label)
		var slider := HSlider.new()
		slider.max_value = 1
		slider.step = 0.01
		slider.value = volumes[bus]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(value: float) -> void: set_volume(bus, value))
		row.add_child(slider)
		var mute := CheckButton.new()
		mute.text = "음소거"
		mute.button_pressed = muted[bus]
		mute.toggled.connect(func(value: bool) -> void: set_muted(bus, value))
		row.add_child(mute)
	var close := Button.new()
	close.text = "닫기 [Esc]"
	close.pressed.connect(settings.hide)
	column.add_child(close)
	settings.popup_hide.connect(func() -> void: play_sfx("close"))
