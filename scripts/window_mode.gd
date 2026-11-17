# Atalho global Alt+Enter para alternar entre janela e tela cheia em qualquer tela do jogo.
extends Node

const FULLSCREEN_MODES := [
	DisplayServer.WINDOW_MODE_FULLSCREEN,
	DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
]

var _restore_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_MAXIMIZED


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.window_get_mode()
	if not is_fullscreen(mode) and mode != DisplayServer.WINDOW_MODE_MINIMIZED:
		_restore_mode = mode


func _input(event: InputEvent) -> void:
	if is_toggle_event(event):
		toggle_fullscreen()
		var vp := get_viewport()
		if vp:
			vp.set_input_as_handled()


static func is_toggle_event(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return (
		key.pressed
		and not key.echo
		and key.alt_pressed
		and not key.ctrl_pressed
		and not key.meta_pressed
		and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER)
	)


static func is_fullscreen(mode: DisplayServer.WindowMode) -> bool:
	return mode in FULLSCREEN_MODES


func next_mode_for(current_mode: DisplayServer.WindowMode) -> DisplayServer.WindowMode:
	if is_fullscreen(current_mode):
		return _restore_mode
	if current_mode != DisplayServer.WINDOW_MODE_MINIMIZED:
		_restore_mode = current_mode
	return DisplayServer.WINDOW_MODE_FULLSCREEN


func toggle_fullscreen() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var current := DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(next_mode_for(current))
