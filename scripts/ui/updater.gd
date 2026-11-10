extends Control

## Updater Automático do GT3 Time Attack
## Gerencia o download inicial do pacote pesado (base_data.pck) e hot-updates (patch.pck)

const CURRENT_CLIENT_VERSION: int = 1
const VERSION_URL: String = "https://raw.githubusercontent.com/daviml/gt3-godot/main/version.json"

const BASE_PCK_PATH: String = "user://base_data.pck"
const PATCH_PCK_PATH: String = "user://patch.pck"
const LOCAL_VERSION_PATH: String = "user://installed_version.json"

var http_request: HTTPRequest
var status_label: Label
var details_label: Label
var progress_bar: ProgressBar
var btn_skip: Button

var is_downloading: bool = false
var target_save_path: String = ""
var next_version_to_save: int = 1

func _ready() -> void:
	_setup_ui()
	_setup_network()
	
	# Se estiver rodando dentro do editor do Godot, os arquivos locais já estão em res://.
	# Entramos direto na garagem para não atrapalhar o desenvolvimento.
	if OS.has_feature("editor"):
		status_label.text = "Modo Editor detectado. Iniciando desenvolvimento..."
		_load_existing_packs()
		await get_tree().create_timer(0.4).timeout
		_start_game()
		return
	
	# Verifica se precisa do download inicial dos dados completos
	var has_base_data: bool = FileAccess.file_exists(BASE_PCK_PATH)
	
	if not has_base_data:
		status_label.text = "Primeira inicialização: Conectando para baixar recursos..."
		_check_updates(true)
	else:
		status_label.text = "Verificando atualizações..."
		_check_updates(false)

func _setup_ui() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	
	# Fundo escuro esportivo
	var bg = ColorRect.new()
	bg.color = Color("#0b0d10")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	
	# Container centralizado
	var center = CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(500, 260)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)
	
	# Título do jogo
	var title = Label.new()
	title.text = "GT3 TIME ATTACK"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color("#ffffff"))
	vbox.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "INTERLAGOS • SIMULADOR & ARCADE"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#8892a0"))
	vbox.add_child(subtitle)
	
	# Espaçador
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 16)
	vbox.add_child(spacer)
	
	# Status
	status_label = Label.new()
	status_label.text = "Inicializando..."
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 15)
	status_label.add_theme_color_override("font_color", Color("#d0d6e0"))
	vbox.add_child(status_label)
	
	# Barra de Progresso estilizada
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(500, 22)
	progress_bar.min_value = 0.0
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = true
	vbox.add_child(progress_bar)
	
	# Detalhes (MB baixados / total)
	details_label = Label.new()
	details_label.text = ""
	details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	details_label.add_theme_font_size_override("font_size", 12)
	details_label.add_theme_color_override("font_color", Color("#6e7887"))
	vbox.add_child(details_label)
	
	# Botão de Pular / Jogar Offline
	btn_skip = Button.new()
	btn_skip.text = "Jogar Offline"
	btn_skip.custom_minimum_size = Vector2(160, 36)
	btn_skip.size_flags_horizontal = SIZE_SHRINK_CENTER
	btn_skip.pressed.connect(_on_skip_pressed)
	# Fica oculto no início; aparece após timeout ou erro
	btn_skip.visible = false
	vbox.add_child(btn_skip)

func _setup_network() -> void:
	http_request = HTTPRequest.new()
	http_request.timeout = 15.0
	add_child(http_request)

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

func _check_updates(is_first_install: bool) -> void:
	# Timer de tolerância para mostrar botão de pular caso conexão demore
	get_tree().create_timer(6.0).timeout.connect(func():
		if is_downloading or not is_inside_tree():
			return
		if FileAccess.file_exists(BASE_PCK_PATH):
			btn_skip.visible = true
	)
	
	http_request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
		if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
			print("[Updater] Falha ao consultar version.json (Code: %d). Iniciando offline." % response_code)
			status_label.text = "Servidor indisponível. Iniciando offline..."
			_fallback_or_start(is_first_install)
			return
			
		var data = JSON.parse_string(body.get_string_from_utf8())
		if not data or not data is Dictionary:
			print("[Updater] JSON de versão inválido.")
			_fallback_or_start(is_first_install)
			return
			
		var remote_ver: int = int(data.get("version", 1))
		var base_url: String = data.get("base_data_url", "")
		var patch_url: String = data.get("patch_url", "")
		var local_ver: int = _get_local_version()
		
		next_version_to_save = remote_ver
		
		if is_first_install:
			# Primeiro acesso: precisa baixar base_data.pck
			if base_url.is_empty():
				status_label.text = "Erro: URL do pacote base não configurada."
				btn_skip.visible = true
				return
			status_label.text = "Baixando pacote inicial de recursos (~250 MB)..."
			_start_file_download(base_url, BASE_PCK_PATH)
		elif remote_ver > local_ver and not patch_url.is_empty():
			# Atualização incremental disponível
			status_label.text = "Nova atualização detectada (v%d)! Baixando patch..." % remote_ver
			_start_file_download(patch_url, PATCH_PCK_PATH)
		else:
			status_label.text = "Jogo atualizado!"
			await get_tree().create_timer(0.4).timeout
			_load_existing_packs()
			_start_game()
	, CONNECT_ONE_SHOT)
	
	http_request.request(VERSION_URL)

func _start_file_download(url: String, save_path: String) -> void:
	is_downloading = true
	target_save_path = save_path
	btn_skip.visible = false
	
	# Arquivo temporário durante o download para não corromper se interrompido
	var temp_path = save_path + ".tmp"
	http_request.download_file = temp_path
	
	http_request.request_completed.connect(func(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
		is_downloading = false
		
		if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
			# Renomeia o temporário para o destino oficial
			if FileAccess.file_exists(save_path):
				DirAccess.remove_absolute(save_path)
			DirAccess.rename_absolute(temp_path, save_path)
			
			_save_local_version(next_version_to_save)
			status_label.text = "Download concluído com sucesso!"
			details_label.text = ""
			progress_bar.value = 100.0
			
			await get_tree().create_timer(0.5).timeout
			_load_existing_packs()
			_start_game()
		else:
			print("[Updater] Falha no download (Result: %d, Code: %d)" % [result, response_code])
			status_label.text = "Erro no download. Verifique sua conexão."
			btn_skip.text = "Tentar Jogar Mesmo Assim"
			btn_skip.visible = true
	, CONNECT_ONE_SHOT)
	
	var err = http_request.request(url)
	if err != OK:
		print("[Updater] Erro ao disparar requisição de download: ", err)
		status_label.text = "Falha ao iniciar download."
		btn_skip.visible = true

func _process(_delta: float) -> void:
	if not is_downloading or not is_instance_valid(http_request):
		return
		
	var downloaded: int = http_request.get_downloaded_bytes()
	var total: int = http_request.get_body_size()
	
	if total > 0:
		var pct: float = (float(downloaded) / float(total)) * 100.0
		progress_bar.value = pct
		
		var down_mb: float = float(downloaded) / (1024.0 * 1024.0)
		var total_mb: float = float(total) / (1024.0 * 1024.0)
		details_label.text = "%.1f MB / %.1f MB (%.0f%%)" % [down_mb, total_mb, pct]
	elif downloaded > 0:
		var down_mb: float = float(downloaded) / (1024.0 * 1024.0)
		details_label.text = "Baixando: %.1f MB..." % down_mb

func _fallback_or_start(is_first_install: bool) -> void:
	if is_first_install and not FileAccess.file_exists(BASE_PCK_PATH):
		status_label.text = "Sem conexão e sem dados locais. Conecte-se à internet."
		btn_skip.visible = true
	else:
		_load_existing_packs()
		_start_game()

func _load_existing_packs() -> void:
	# 1. Carrega o pacote de dados base
	if FileAccess.file_exists(BASE_PCK_PATH):
		var ok = ProjectSettings.load_resource_pack(BASE_PCK_PATH)
		print("[Updater] Pacote base carregado: ", ok)
		
	# 2. Carrega o patch por cima (sobrescrevendo arquivos que foram atualizados)
	if FileAccess.file_exists(PATCH_PCK_PATH):
		var ok_patch = ProjectSettings.load_resource_pack(PATCH_PCK_PATH)
		print("[Updater] Patch incremental carregado: ", ok_patch)

func _on_skip_pressed() -> void:
	_load_existing_packs()
	_start_game()

func _start_game() -> void:
	get_tree().change_scene_to_file("res://scenes/garagem.tscn")
