# Tokens visuais, tipografia, StyleBoxes e cálculo responsivo LMU para Desktop e Mobile.
class_name LmuTheme
extends RefCounted

const BG_DARK := Color(0.024, 0.031, 0.047, 0.95)
const BG_BACKDROP := Color(0.024, 0.031, 0.047, 0.94)
const BG_HEADER := Color(0.031, 0.043, 0.063, 0.96)
const BG_PANEL := Color(0.055, 0.071, 0.102, 0.92)
const BG_PANEL_DEEP := Color(0.035, 0.047, 0.067, 0.96)
const BG_CHIP := Color(0.071, 0.090, 0.125, 0.90)
const BG_CHIP_HOVER := Color(0.110, 0.141, 0.196, 0.96)
const BG_INPUT := Color(0.051, 0.071, 0.102, 0.95)

const ACCENT_RED := Color("#e10600")
const ACCENT_RED_BRIGHT := Color("#ff3b30")
const ACCENT_RED_DARK := Color("#b30006")
const ACCENT_GOLD := Color("#ffd700")
const ACCENT_AMBER := Color("#f2c230")
const ACCENT_GREEN := Color("#2fd36b")
const ACCENT_BLUE := Color("#3d8bff")

const TEXT_WHITE := Color("#f2f4f8")
const TEXT_SLATE := Color("#cbd5e1")
const TEXT_MUTED := Color(1.0, 1.0, 1.0, 0.58)
const TEXT_DIM := Color(1.0, 1.0, 1.0, 0.42)

const BORDER_SUBTLE := Color(1.0, 1.0, 1.0, 0.14)
const BORDER_SOFT := Color(1.0, 1.0, 1.0, 0.08)
const BORDER_BRIGHT := Color(1.0, 1.0, 1.0, 0.35)

const TAG_DR_BG := Color("#b5833c")
const TAG_SR_BG := Color("#3d6a9a")

static var _font_cache := {}
static var _mono_cache: Font


static func font(weight := 600, italic := false) -> Font:
	var key := "%d_%s" % [weight, "i" if italic else "n"]
	if _font_cache.has(key):
		return _font_cache[key]
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Roboto", "sans-serif"])
	f.font_weight = weight
	f.font_italic = italic
	_font_cache[key] = f
	return f


static func mono_font() -> Font:
	if _mono_cache == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Consolas", "Droid Sans Mono", "monospace"])
		_mono_cache = f
	return _mono_cache


static func get_safe_insets(viewport_size: Vector2) -> Dictionary:
	var res := {"left": 0.0, "right": 0.0, "top": 0.0, "bottom": 0.0}
	if not OS.has_feature("mobile"):
		return res
	var scr := Vector2(DisplayServer.screen_get_size())
	if scr.x <= 0.0 or scr.y <= 0.0 or viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return res
	var safe := DisplayServer.get_display_safe_area()
	var sx := viewport_size.x / scr.x
	var sy := viewport_size.y / scr.y
	res.left = maxf(0.0, float(safe.position.x) * sx)
	res.top = maxf(0.0, float(safe.position.y) * sy)
	res.right = maxf(0.0, (scr.x - float(safe.end.x)) * sx)
	res.bottom = maxf(0.0, (scr.y - float(safe.end.y)) * sy)
	return res


static func compute_layout_profile(viewport_size: Vector2, is_mobile := false) -> Dictionary:
	var vp := viewport_size
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = Vector2(1920.0, 1080.0)

	var safe := get_safe_insets(vp)
	var profile := "desktop"
	if vp.x < vp.y:
		profile = "portrait"
	elif is_mobile or vp.y <= 560.0:
		if is_mobile and vp.y >= 700.0 and (vp.x / vp.y) < 1.55:
			profile = "tablet"
		else:
			profile = "mobile_landscape"
	elif vp.x >= 960.0 and vp.y > 560.0:
		profile = "desktop"
	else:
		profile = "tablet"

	var usable_w := maxf(240.0, vp.x - float(safe.left) - float(safe.right))
	var usable_h := maxf(240.0, vp.y - float(safe.top) - float(safe.bottom))

	var is_compact_mobile := (profile == "mobile_landscape" and vp.y <= 480.0)
	var header_h := 42 if is_compact_mobile else (76 if profile == "mobile_landscape" else 56)
	var show_center := (profile == "desktop" or profile == "tablet")

	var pad_x := 32.0
	var pad_y := 18.0
	var home_left_w := 460.0
	var home_right_w := 380.0
	var cars_panel_w := 330.0
	var cars_hide_aero := false
	var cars_pb_horizontal := false
	var cars_grid_cols := 7
	var cars_chip_h := 52
	var font_scale := 1.0

	match profile:
		"desktop":
			pad_x = clampf(vp.x * 0.028, 28.0, 56.0)
			pad_y = clampf(vp.y * 0.018, 14.0, 22.0)
			home_left_w = minf(480.0, usable_w * 0.48)
			home_right_w = 390.0
			cars_panel_w = 330.0
			cars_grid_cols = 7
			cars_chip_h = 52
			font_scale = clampf(minf(vp.x / 1600.0, vp.y / 900.0), 0.85, 1.12)
		"tablet":
			pad_x = 20.0
			pad_y = 14.0
			home_left_w = usable_w * 0.48
			home_right_w = minf(340.0, usable_w * 0.44)
			cars_panel_w = 260.0
			cars_grid_cols = 5
			cars_chip_h = 46
			font_scale = clampf(vp.y / 820.0, 0.78, 0.95)
		"mobile_landscape":
			if is_compact_mobile:
				pad_x = 14.0
				pad_y = 6.0
				home_left_w = usable_w * 0.52
				home_right_w = usable_w * 0.44
				cars_panel_w = 235.0
				cars_hide_aero = true
				cars_pb_horizontal = true
				cars_grid_cols = 7
				cars_chip_h = 36
				font_scale = clampf(vp.y / 440.0, 0.68, 0.88)
			else:
				pad_x = clampf(vp.x * 0.025, 24.0, 48.0)
				pad_y = clampf(vp.y * 0.018, 12.0, 22.0)
				home_left_w = clampf(usable_w * 0.52, 520.0, 920.0)
				home_right_w = clampf(usable_w * 0.42, 420.0, 680.0)
				cars_panel_w = clampf(usable_w * 0.30, 340.0, 480.0)
				cars_hide_aero = false
				cars_pb_horizontal = true
				cars_grid_cols = 5
				cars_chip_h = 72
				font_scale = clampf(vp.y / 600.0, 1.35, 1.85)
		"portrait":
			pad_x = 14.0
			pad_y = 12.0
			home_left_w = usable_w - pad_x * 2.0
			home_right_w = usable_w - pad_x * 2.0
			cars_panel_w = usable_w - pad_x * 2.0
			cars_hide_aero = false
			cars_pb_horizontal = true
			cars_grid_cols = 3
			cars_chip_h = 44
			font_scale = clampf(vp.x / 460.0, 0.72, 0.92)

	return {
		"profile": profile,
		"is_compact_mobile": is_compact_mobile,
		"viewport_size": vp,
		"is_mobile": is_mobile,
		"safe_left": float(safe.left),
		"safe_right": float(safe.right),
		"safe_top": float(safe.top),
		"safe_bottom": float(safe.bottom),
		"usable_w": usable_w,
		"usable_h": usable_h,
		"header_height": header_h,
		"show_header_center": show_center,
		"pad_x": pad_x,
		"pad_y": pad_y,
		"home_left_width": home_left_w,
		"home_right_width": home_right_w,
		"cars_panel_width": cars_panel_w,
		"cars_hide_aero": cars_hide_aero,
		"cars_pb_horizontal": cars_pb_horizontal,
		"cars_grid_cols": cars_grid_cols,
		"cars_chip_height": cars_chip_h,
		"font_scale": font_scale,
	}


static func make_label(text: String, size: int, color := TEXT_WHITE, weight := 600, italic := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(8, size))
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_override("font", font(weight, italic))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_style(bg := BG_PANEL, border := BORDER_SUBTLE, radius := 6, pad_h := 14, pad_v := 10, left_accent := Color.TRANSPARENT) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	if left_accent.a > 0.01:
		sb.border_width_left = 4
		sb.border_color = left_accent
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad_h
	sb.content_margin_right = pad_h
	sb.content_margin_top = pad_v
	sb.content_margin_bottom = pad_v
	return sb


static func apply_button_styles(b: Button, kind := "outline", radius := 4, pad_h := 14, pad_v := 8) -> void:
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_override("font", font(700))
	for st in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(radius)
		sb.content_margin_left = pad_h
		sb.content_margin_right = pad_h
		sb.content_margin_top = pad_v
		sb.content_margin_bottom = pad_v
		sb.set_border_width_all(1)
		match kind:
			"primary":
				sb.bg_color = ACCENT_RED if st == "normal" else (ACCENT_RED_BRIGHT if st == "hover" else (ACCENT_RED_DARK if st == "pressed" else Color(0.35, 0.1, 0.1, 0.6)))
				sb.border_color = Color(1, 1, 1, 0.25 if st == "hover" else 0.05)
			"active":
				sb.bg_color = Color(ACCENT_RED.r, ACCENT_RED.g, ACCENT_RED.b, 0.26 if st == "normal" else 0.38)
				sb.border_color = ACCENT_RED
			"arcade":
				sb.bg_color = Color(ACCENT_AMBER.r, ACCENT_AMBER.g, ACCENT_AMBER.b, 0.16 if st == "normal" else 0.28)
				sb.border_color = ACCENT_AMBER
			"ghost":
				sb.bg_color = Color(1, 1, 1, 0.0 if st == "normal" else (0.08 if st == "hover" else 0.14))
				sb.border_color = Color.TRANSPARENT
				sb.set_border_width_all(0)
			"tab_active":
				sb.bg_color = Color(1, 1, 1, 0.05 if st == "normal" else 0.09)
				sb.set_border_width_all(0)
				sb.border_width_bottom = 2
				sb.border_color = Color.WHITE
				sb.set_corner_radius_all(0)
			"tab_idle":
				sb.bg_color = Color(1, 1, 1, 0.0 if st == "normal" else 0.05)
				sb.set_border_width_all(0)
				sb.border_width_bottom = 2
				sb.border_color = Color(1, 1, 1, 0.25 if st == "hover" else 0.0)
				sb.set_corner_radius_all(0)
			_:
				sb.bg_color = Color(1, 1, 1, 0.07 if st == "normal" else (0.16 if st == "hover" else (0.24 if st == "pressed" else 0.03)))
				sb.border_color = Color(1, 1, 1, 0.20 if st == "normal" else 0.45)
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", ACCENT_AMBER if kind == "arcade" else TEXT_WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)


static func input_style(focused := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = BG_INPUT
	sb.border_color = ACCENT_RED if focused else Color(1, 1, 1, 0.22)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

