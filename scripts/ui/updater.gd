extends Control

## Auto-Updater do GT3 Time Attack
## Verifica se há novidades e baixa apenas o patch leve (2~4 MB). Se estiver offline ou atualizado, entra direto no jogo!

const CURRENT_CLIENT_VERSION: int = 6
const VERSION_URL: String = "https://raw.githubusercontent.com/daviml/gt3-godot/main/version.json"
const PATCH_PCK_PATH: String = "user://patch.pck"
const LOCAL_VERSION_PATH: String = "user://installed_version.json"
const GARAGEM_SCENE: String = "res://scenes/garagem.tscn"

const HTTP_HEADERS: PackedStringArray = [
	"User-Agent: GT3TimeAttack-Mobile/1.0",
	"Accept: application/json, */*"
]

var http_version: HTTPRequest
var http_download: HTTPRequest

var status_label: Label
var details_label: Label
var progress_bar: ProgressBar
var is_downloading: bool = false
var is_loading_game: bool = false
var next_version_to_save: int = CURRENT_CLIENT_VERSION
var _initial_car_id: String = ""
var _initial_car_glb: String = ""
var _garagem_done: bool = false
var _car_done: bool = false
var _garagem_packed: PackedScene = null

func _ready() -> void:
	_setup_ui()
	_cleanup_stale_or_incompatible_patches()
	_setup_network()
	
	# No editor, entra direto
	if OS.has_feature("editor"):
		_finish_and_enter_game()
		return
		
	status_label.text = "Verificando atualizações..."
	_check_for_patches()

func _setup_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	
	var bg = ColorRect.new()
	bg.color = Color("#0b0d10")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(850, 320)
	vbox.add_theme_constant_override("separation", 18)
	center.add_child(vbox)
	
	var title = Label.new()
	title.text = "GT3 TIME ATTACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "INTERLAGOS • SIMULADOR & ARCADE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color("#8e9aa8"))
	vbox.add_child(subtitle)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	status_label = Label.new()
	status_label.text = "Iniciando..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 22)
	status_label.add_theme_color_override("font_color", Color("#e2e8f0"))
	vbox.add_child(status_label)
	
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(850, 32)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = true
	progress_bar.add_theme_font_size_override("font_size", 18)
	progress_bar.visible = false
	vbox.add_child(progress_bar)
	
	details_label = Label.new()
	details_label.text = ""
	details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details_label.add_theme_font_size_override("font_size", 18)
	details_label.add_theme_color_override("font_color", Color("#94a3b8"))
	details_label.visible = false
	vbox.add_child(details_label)

func _setup_network() -> void:
	http_version = HTTPRequest.new()
	http_version.timeout = 1.5 # Timeout rápido de 1.5s para não prender o jogador
	add_child(http_version)
	
	http_download = HTTPRequest.new()
	http_download.timeout = 30.0
	http_download.use_threads = true
	add_child(http_download)

func _get_saved_version_on_disk() -> int:
	if not FileAccess.file_exists(LOCAL_VERSION_PATH):
		return 0
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.READ)
	if not f:
		return 0
	var json = JSON.parse_string(f.get_as_text())
	if json and json is Dictionary and json.has("version"):
		return int(json["version"])
	return 0

func _get_local_version() -> int:
	var saved = _get_saved_version_on_disk()
	return maxi(saved, CURRENT_CLIENT_VERSION)

func _save_local_version(ver: int) -> void:
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": ver}))

func _is_pck_compatible(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var f = FileAccess.open(path, FileAccess.READ)
	if not f:
		return false
	if f.get_length() < 20:
		f.close()
		return false
	var magic = f.get_32()
	# "GDPC" em little-endian é 0x43504447
	if magic != 0x43504447:
		f.close()
		return false
	var _pck_format = f.get_32()
	var major = f.get_32()
	var minor = f.get_32()
	f.close()
	var engine_info = Engine.get_version_info()
	var cur_major = int(engine_info.get("major", 0))
	var cur_minor = int(engine_info.get("minor", 0))
	if major != cur_major or minor != cur_minor:
		print("[Updater] PCK gerado para Godot %d.%d, mas engine atual é %d.%d! Incompatível." % [major, minor, cur_major, cur_minor])
		return false
	return true

func _cleanup_stale_or_incompatible_patches() -> void:
	var saved_ver = _get_saved_version_on_disk()
	# Se a versão base do APK for maior ou igual ao patch que estava salvo,
	# o APK atual já tem tudo atualizado; descarta o patch antigo para evitar conflitos.
	if CURRENT_CLIENT_VERSION >= saved_ver:
		if FileAccess.file_exists(PATCH_PCK_PATH):
			print("[Updater] Novo APK instalado (v%d >= v%d). Removendo patch antigo..." % [CURRENT_CLIENT_VERSION, saved_ver])
			DirAccess.remove_absolute(PATCH_PCK_PATH)
		_save_local_version(CURRENT_CLIENT_VERSION)
	elif FileAccess.file_exists(PATCH_PCK_PATH):
		if not _is_pck_compatible(PATCH_PCK_PATH):
			print("[Updater] Patch existente é incompatível com o Godot atual. Removendo...")
			DirAccess.remove_absolute(PATCH_PCK_PATH)
			_save_local_version(CURRENT_CLIENT_VERSION)

func _check_for_patches() -> void:
	http_version.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[Updater] Sem internet ou servidor inacessível (%d). Entrando no jogo..." % response_code)
			_finish_and_enter_game()
			return
			
		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data or not data is Dictionary:
			_finish_and_enter_game()
			return
			
		var remote_ver: int = int(data.get("version", 1))
		var patch_url: String = data.get("patch_url", "")
		var local_ver: int = _get_local_version()
		
		# Só baixa se a versão remota for estritamente mais recente E houver URL de patch válida
		if remote_ver > local_ver and not patch_url.is_empty():
			next_version_to_save = remote_ver
			status_label.text = "Nova atualização encontrada (v%d)! Baixando..." % remote_ver
			progress_bar.visible = true
			details_label.visible = true
			_download_patch(patch_url)
		else:
			status_label.text = "Jogo atualizado!"
			_finish_and_enter_game()
	, CONNECT_ONE_SHOT)
	
	var err = http_version.request(VERSION_URL, HTTP_HEADERS)
	if err != OK:
		_finish_and_enter_game()

func _download_patch(url: String) -> void:
	is_downloading = true
	var temp_patch = PATCH_PCK_PATH + ".tmp"
	http_download.download_file = temp_patch
	
	http_download.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading = false
		
		if result == HTTPRequest.RESULT_SUCCESS and (response_code == 200 or response_code == 302):
			if not _is_pck_compatible(temp_patch):
				print("[Updater] Patch baixado é incompatível com a versão do engine Godot! Descartando.")
				DirAccess.remove_absolute(temp_patch)
				status_label.text = "Atualização incompatível com este app."
				await get_tree().create_timer(1.0).timeout
			else:
				if FileAccess.file_exists(PATCH_PCK_PATH):
					DirAccess.remove_absolute(PATCH_PCK_PATH)
				DirAccess.rename_absolute(temp_patch, PATCH_PCK_PATH)
				_save_local_version(next_version_to_save)
				status_label.text = "Atualização instalada com sucesso!"
				progress_bar.value = 100.0
				await get_tree().create_timer(0.4).timeout
		else:
			print("[Updater] Falha ao baixar patch (%d). Usando versão instalada." % response_code)
			
		_finish_and_enter_game()
	, CONNECT_ONE_SHOT)
	
	var err = http_download.request(url, HTTP_HEADERS)
	if err != OK:
		_finish_and_enter_game()

func _process(delta: float) -> void:
	if is_downloading and is_instance_valid(http_download):
		var downloaded: int = http_download.get_downloaded_bytes()
		var total: int = http_download.get_body_size()
		if total > 0:
			var pct: float = (float(downloaded) / float(total)) * 100.0
			progress_bar.value = pct
			var down_mb: float = float(downloaded) / (1024.0 * 1024.0)
			var total_mb: float = float(total) / (1024.0 * 1024.0)
			details_label.text = "%.1f MB / %.1f MB (%.0f%%)" % [down_mb, total_mb, pct]
		return

	if is_loading_game:
		var gar_pct: float = 100.0 if _garagem_done else 0.0
		var car_pct: float = 100.0 if _car_done else 0.0

		if not _garagem_done:
			var g_prog: Array = []
			var g_status := ResourceLoader.load_threaded_get_status(GARAGEM_SCENE, g_prog)
			if g_prog.size() > 0:
				gar_pct = clampf(float(g_prog[0]) * 100.0, 0.0, 100.0)
			match g_status:
				ResourceLoader.THREAD_LOAD_LOADED:
					_garagem_packed = ResourceLoader.load_threaded_get(GARAGEM_SCENE) as PackedScene
					_garagem_done = true
					gar_pct = 100.0
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					print("[Updater] Falha no carregamento assíncrono da garagem (%d). Fallback direto." % g_status)
					_garagem_done = true
					gar_pct = 100.0

		if not _car_done:
			var c_prog: Array = []
			var c_status := ResourceLoader.load_threaded_get_status(_initial_car_glb, c_prog)
			if c_prog.size() > 0:
				car_pct = clampf(float(c_prog[0]) * 100.0, 0.0, 100.0)
			match c_status:
				ResourceLoader.THREAD_LOAD_LOADED:
					var car_scene := ResourceLoader.load_threaded_get(_initial_car_glb) as PackedScene
					Game.cache_car_scene(_initial_car_id, car_scene)
					_car_done = true
					car_pct = 100.0
				ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
					print("[Updater] Falha ao pré-carregar carro inicial (%d): %s" % [c_status, _initial_car_glb])
					_car_done = true
					car_pct = 100.0

		var combined_pct: float = gar_pct * 0.2 + car_pct * 0.8
		progress_bar.value = maxf(progress_bar.value, minf(combined_pct, 100.0 if (_garagem_done and _car_done) else 99.0))

		if _garagem_done and _car_done:
			progress_bar.value = 100.0
			is_loading_game = false
			if _garagem_packed:
				get_tree().change_scene_to_packed.call_deferred(_garagem_packed)
			else:
				get_tree().change_scene_to_file.call_deferred(GARAGEM_SCENE)

func _load_existing_patch() -> void:
	if FileAccess.file_exists(PATCH_PCK_PATH):
		if not _is_pck_compatible(PATCH_PCK_PATH):
			print("[Updater] Patch incompatível ignorado e removido.")
			DirAccess.remove_absolute(PATCH_PCK_PATH)
			return
		var ok = ProjectSettings.load_resource_pack(PATCH_PCK_PATH)
		print("[Updater] patch.pck carregado com sucesso: ", ok)
		if not ok:
			DirAccess.remove_absolute(PATCH_PCK_PATH)

func _finish_and_enter_game() -> void:
	if is_loading_game:
		return
	is_loading_game = true
	
	_load_existing_patch()
	
	# No editor ou comando com argumento de pista direta, pula a garagem
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--car=") or a.begins_with("--shot=") or a == "--auto":
			is_loading_game = false
			get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
			return
			
	_initial_car_id = Game.car_id
	_initial_car_glb = Game.get_car_glb_path(_initial_car_id)
	var car_info := Game.get_car_info(_initial_car_id)
	var car_name := String(car_info.get("name", _initial_car_id))

	status_label.text = "Carregando garagem..."
	progress_bar.visible = true
	progress_bar.value = 5.0
	details_label.text = "Pré-carregando: %s" % car_name
	details_label.visible = true

	_garagem_done = false
	_garagem_packed = null
	var err = ResourceLoader.load_threaded_request(GARAGEM_SCENE, "", true)
	if err != OK:
		print("[Updater] Falha ao iniciar carregamento assíncrono da garagem (%d). Fallback direto." % err)
		_garagem_done = true

	if _initial_car_glb.is_empty() or Game.get_cached_car_scene(_initial_car_id) != null:
		_car_done = true
	else:
		_car_done = false
		var car_err = ResourceLoader.load_threaded_request(_initial_car_glb, "PackedScene", true)
		if car_err != OK:
			print("[Updater] Falha ao iniciar pré-carga do carro (%d): %s" % [car_err, _initial_car_glb])
			_car_done = true

	if _garagem_done and _car_done:
		is_loading_game = false
		get_tree().change_scene_to_file.call_deferred(GARAGEM_SCENE)
