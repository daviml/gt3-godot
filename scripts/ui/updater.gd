extends Control

## Auto-Updater do GT3 Time Attack
## Verifica se há novidades e baixa apenas o patch leve (2~4 MB). Se estiver offline, entra direto no jogo!

const CURRENT_CLIENT_VERSION: int = 1
const VERSION_URL: String = "https://raw.githubusercontent.com/daviml/gt3-godot/main/version.json"
const PATCH_PCK_PATH: String = "user://patch.pck"
const LOCAL_VERSION_PATH: String = "user://installed_version.json"

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
var next_version_to_save: int = 1

func _ready() -> void:
	_setup_ui()
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
	http_version.timeout = 4.0 # Timeout rápido de 4s para não prender o jogador
	add_child(http_version)
	
	http_download = HTTPRequest.new()
	http_download.timeout = 30.0
	http_download.use_threads = true
	add_child(http_download)

func _get_local_version() -> int:
	if not FileAccess.file_exists(LOCAL_VERSION_PATH):
		return CURRENT_CLIENT_VERSION
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.READ)
	if not f:
		return CURRENT_CLIENT_VERSION
	var json = JSON.parse_string(f.get_as_text())
	if json and json.has("version"):
		return int(json["version"])
	return CURRENT_CLIENT_VERSION

func _save_local_version(ver: int) -> void:
	var f = FileAccess.open(LOCAL_VERSION_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"version": ver}))

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
		
		# Se há um patch mais recente e a URL é válida
		if remote_ver > local_ver and not patch_url.is_empty():
			next_version_to_save = remote_ver
			status_label.text = "Nova atualização encontrada (v%d)! Baixando..." % remote_ver
			progress_bar.visible = true
			details_label.visible = true
			_download_patch(patch_url)
		else:
			status_label.text = "Jogo atualizado!"
			await get_tree().create_timer(0.3).timeout
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

func _process(_delta: float) -> void:
	if not is_downloading or not is_instance_valid(http_download):
		return
		
	var downloaded: int = http_download.get_downloaded_bytes()
	var total: int = http_download.get_body_size()
	
	if total > 0:
		var pct: float = (float(downloaded) / float(total)) * 100.0
		progress_bar.value = pct
		var down_mb: float = float(downloaded) / (1024.0 * 1024.0)
		var total_mb: float = float(total) / (1024.0 * 1024.0)
		details_label.text = "%.1f MB / %.1f MB (%.0f%%)" % [down_mb, total_mb, pct]

func _load_existing_patch() -> void:
	if FileAccess.file_exists(PATCH_PCK_PATH):
		var ok = ProjectSettings.load_resource_pack(PATCH_PCK_PATH)
		print("[Updater] patch.pck carregado com sucesso: ", ok)

func _finish_and_enter_game() -> void:
	_load_existing_patch()
	get_tree().change_scene_to_file.call_deferred("res://scenes/garagem.tscn")
