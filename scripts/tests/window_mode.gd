# Testa o atalho global Alt+Enter (WindowMode): detecção de evento e alternância de modo de janela.
# uso: godot --headless --path . --script res://scripts/tests/window_mode.gd
extends SceneTree

const WindowModeScript := preload("res://scripts/window_mode.gd")
var ok := true


func check(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FALHOU ") + msg)
	ok = ok and cond


func _make_key(keycode: Key, pressed := true, alt := false, ctrl := false, meta := false, echo := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.pressed = pressed
	e.alt_pressed = alt
	e.ctrl_pressed = ctrl
	e.meta_pressed = meta
	e.echo = echo
	return e


func _initialize() -> void:
	_run()
	print("TUDO OK" if ok else "HOUVE FALHAS")
	quit(0 if ok else 1)


func _run() -> void:
	print("detecção do atalho Alt+Enter")
	check(WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, true, true)), "Alt+Enter é reconhecido")
	check(WindowModeScript.is_toggle_event(_make_key(KEY_KP_ENTER, true, true)), "Alt+KP_Enter é reconhecido")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, true, false)), "Enter puro não alterna")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, false, true)), "soltar Alt+Enter não alterna")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, true, true, false, false, true)), "echo de Alt+Enter é ignorado")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, true, true, true, false)), "Ctrl+Alt+Enter é ignorado")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_ENTER, true, true, false, true)), "Meta+Alt+Enter é ignorado")
	check(not WindowModeScript.is_toggle_event(_make_key(KEY_SPACE, true, true)), "Alt+Space não alterna")

	print("alternância de modos")
	var wm: Node = WindowModeScript.new()
	check(wm.next_mode_for(DisplayServer.WINDOW_MODE_MAXIMIZED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "maximizado -> tela cheia")
	check(wm.next_mode_for(DisplayServer.WINDOW_MODE_FULLSCREEN) == DisplayServer.WINDOW_MODE_MAXIMIZED, "tela cheia -> volta para maximizado")
	check(wm.next_mode_for(DisplayServer.WINDOW_MODE_WINDOWED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "janela -> tela cheia")
	check(wm.next_mode_for(DisplayServer.WINDOW_MODE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "tela cheia -> volta para janela")
	check(wm.next_mode_for(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "tela cheia exclusiva -> sai para janela anterior")
	wm.free()

	print("autoload ativo na árvore")
	var autoload_node := root.get_node_or_null("WindowMode")
	check(autoload_node != null, "autoload WindowMode carregado em /root/WindowMode")
	if autoload_node:
		check(autoload_node.process_mode == Node.PROCESS_MODE_ALWAYS, "WindowMode continua ativo mesmo pausado")
