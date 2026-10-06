extends RefCounted

const AdminSettingsPanelScript = preload("res://scripts/admin_settings_panel.gd")
const KoreanFont = preload("res://assets/fonts/NotoSansKR-VariableFont_wght.ttf")
const TRANSITION_SECONDS := 1.0

var _theme: Theme


func build(root: Control, actions: Dictionary) -> Dictionary:
	var nodes := {}
	nodes.bg_view = _texture_layer(root, "BackgroundView")
	nodes.cam_view = _texture_layer(root, "CameraView")
	nodes.chroma_material = ShaderMaterial.new()
	nodes.chroma_material.shader = load("res://shaders/chroma_key.gdshader")
	nodes.cam_view.material = nodes.chroma_material
	var fallback := Image.create(2, 2, false, Image.FORMAT_RGB8)
	fallback.fill(Color("#0b0c10"))
	nodes.camera_texture = ImageTexture.create_from_image(fallback)
	nodes.cam_view.texture = nodes.camera_texture
	nodes.chroma_material.set_shader_parameter("source_texture", nodes.camera_texture)
	nodes.front_view = _texture_layer(root, "ForegroundView")
	nodes.standby_video = _make_video_player(root, "standby.ogv")
	nodes.select_video = _make_video_player(root, "select.ogv")
	nodes.transition_video_stream = load("res://assets/videos/transition.ogv") as VideoStream
	nodes.transition_timer = Timer.new()
	nodes.transition_timer.one_shot = true
	nodes.transition_timer.wait_time = TRANSITION_SECONDS
	nodes.transition_timer.timeout.connect(actions.transition_finished)
	root.add_child(nodes.transition_timer)

	nodes.ui_layer = Control.new()
	nodes.ui_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(nodes.ui_layer)
	_theme = Theme.new()
	_theme.default_font = KoreanFont
	_theme.default_font_size = 28
	nodes.ui_layer.theme = _theme

	nodes.prompt = Label.new()
	nodes.prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nodes.prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nodes.prompt.add_theme_color_override("font_color", Color.CYAN)
	nodes.prompt.add_theme_font_size_override("font_size", 100)
	nodes.prompt.text = "아무 키나 눌러주세요"
	nodes.prompt.theme = _theme
	root.add_child(nodes.prompt)

	nodes.navigation_cursor = Panel.new()
	nodes.navigation_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes.navigation_cursor.visible = false
	var cursor_style := StyleBoxFlat.new()
	cursor_style.bg_color = Color(0, 0, 0, 0)
	cursor_style.border_color = Color("#66fcf1")
	cursor_style.set_border_width_all(6)
	cursor_style.set_corner_radius_all(14)
	nodes.navigation_cursor.add_theme_stylebox_override("panel", cursor_style)
	root.add_child(nodes.navigation_cursor)

	nodes.timer_label = Label.new()
	nodes.timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nodes.timer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nodes.timer_label.add_theme_font_size_override("font_size", 300)
	nodes.timer_label.add_theme_color_override("font_color", Color.WHITE)
	nodes.timer_label.add_theme_color_override("font_outline_color", Color.BLACK)
	nodes.timer_label.add_theme_constant_override("outline_size", 10)
	nodes.timer_label.add_theme_color_override("font_shadow_color", Color(0, 1, 1, 0.7))
	nodes.timer_label.add_theme_constant_override("shadow_offset_x", 0)
	nodes.timer_label.add_theme_constant_override("shadow_offset_y", 0)
	nodes.ui_layer.add_child(nodes.timer_label)

	nodes.bg_buttons = GridContainer.new()
	nodes.bg_buttons.columns = 3
	nodes.bg_buttons.add_theme_constant_override("h_separation", 50)
	nodes.bg_buttons.add_theme_constant_override("v_separation", 40)
	nodes.ui_layer.add_child(nodes.bg_buttons)

	nodes.result_panel = Control.new()
	nodes.ui_layer.add_child(nodes.result_panel)
	nodes.result_background_view = TextureRect.new()
	nodes.result_background_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nodes.result_background_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nodes.result_background_view.stretch_mode = TextureRect.STRETCH_SCALE
	nodes.result_background_view.texture = load("res://assets/backgrounds/result_background.png")
	nodes.result_background_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes.result_panel.add_child(nodes.result_background_view)
	nodes.result_preview = TextureRect.new()
	nodes.result_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nodes.result_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nodes.result_panel.add_child(nodes.result_preview)
	nodes.qr_view = TextureRect.new()
	nodes.qr_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	nodes.qr_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	nodes.result_panel.add_child(nodes.qr_view)
	var result_actions := VBoxContainer.new()
	nodes.result_panel.add_child(result_actions)
	result_actions.add_theme_constant_override("separation", 20)
	var retry_button := create_button("다시 찍기", actions.retake)
	retry_button.custom_minimum_size = Vector2(400, 100)
	result_actions.add_child(retry_button)
	var home_button := create_button("처음으로 (완료)", actions.home)
	home_button.custom_minimum_size = Vector2(400, 100)
	result_actions.add_child(home_button)

	nodes.status = Label.new()
	nodes.status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	nodes.status.add_theme_font_size_override("font_size", 18)
	nodes.ui_layer.add_child(nodes.status)
	nodes.capture_button = create_button("촬영하기", actions.capture)
	nodes.capture_button.custom_minimum_size = Vector2(224, 102)
	nodes.ui_layer.add_child(nodes.capture_button)
	nodes.capture_button.add_theme_font_size_override("font_size", 51)
	_layout(nodes)

	nodes.admin_panel = AdminSettingsPanelScript.new()
	nodes.admin_panel.theme = _theme
	root.add_child(nodes.admin_panel)

	nodes.capture_flash = ColorRect.new()
	nodes.capture_flash.name = "CaptureFlash"
	nodes.capture_flash.color = Color(1, 1, 1, 0)
	nodes.capture_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nodes.capture_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	nodes.capture_flash.visible = false
	root.add_child(nodes.capture_flash)

	nodes.server_waiting_popup = _build_waiting_popup(nodes.ui_layer)
	return nodes


func create_button(caption: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(160, 58)
	button.add_theme_font_size_override("font_size", 28)
	button.add_theme_color_override("font_color", Color("#323232"))
	button.add_theme_color_override("font_hover_color", Color("#323232"))
	button.add_theme_color_override("font_pressed_color", Color("#323232"))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("#f0f0f0")
	normal.border_color = Color("#a6a6a6")
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	normal.content_margin_left = 18
	normal.content_margin_right = 18
	normal.content_margin_top = 12
	normal.content_margin_bottom = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("#e8e8e8")
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("#c8c8c8")
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("focus", normal)
	button.pressed.connect(callback)
	return button


func _texture_layer(root: Control, node_name: String) -> TextureRect:
	var view := TextureRect.new()
	view.name = node_name
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(view)
	return view


func _make_video_player(root: Control, file_name: String) -> VideoStreamPlayer:
	var player := VideoStreamPlayer.new()
	player.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	player.expand = true
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	player.stream = load("res://assets/videos/" + file_name) as VideoStream
	player.visible = false
	root.add_child(player)
	return player


func _layout(nodes: Dictionary) -> void:
	nodes.prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nodes.prompt.offset_left = -500
	nodes.prompt.offset_right = 500
	nodes.prompt.offset_top = 250
	nodes.prompt.offset_bottom = 450
	nodes.timer_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nodes.timer_label.offset_left = -250
	nodes.timer_label.offset_right = 250
	nodes.timer_label.offset_top = -150
	nodes.timer_label.offset_bottom = 150
	nodes.bg_buttons.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nodes.bg_buttons.offset_left = -920
	nodes.bg_buttons.offset_right = 920
	nodes.bg_buttons.offset_top = -450
	nodes.bg_buttons.offset_bottom = 450
	nodes.result_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	nodes.result_preview.anchor_left = 0
	nodes.result_preview.anchor_right = 0
	nodes.result_preview.anchor_top = 0.5
	nodes.result_preview.anchor_bottom = 0.5
	nodes.result_preview.offset_left = 100
	nodes.result_preview.offset_top = -360
	nodes.result_preview.offset_right = 1380
	nodes.result_preview.offset_bottom = 360
	nodes.qr_view.anchor_left = 1
	nodes.qr_view.anchor_right = 1
	nodes.qr_view.anchor_top = 0
	nodes.qr_view.anchor_bottom = 0
	nodes.qr_view.offset_left = -480
	nodes.qr_view.offset_top = 180
	nodes.qr_view.offset_right = -80
	nodes.qr_view.offset_bottom = 580
	var actions: VBoxContainer = nodes.result_panel.get_child(3)
	actions.anchor_left = 1
	actions.anchor_right = 1
	actions.anchor_top = 1
	actions.anchor_bottom = 1
	actions.offset_left = -480
	actions.offset_top = -400
	actions.offset_right = -80
	actions.offset_bottom = -180
	nodes.status.anchor_left = 0
	nodes.status.anchor_right = 0
	nodes.status.anchor_top = 1
	nodes.status.anchor_bottom = 1
	nodes.status.offset_left = 24
	nodes.status.offset_top = -48
	nodes.status.offset_right = 620
	nodes.status.offset_bottom = -12
	nodes.capture_button.anchor_left = 0.5
	nodes.capture_button.anchor_right = 0.5
	nodes.capture_button.anchor_top = 1
	nodes.capture_button.anchor_bottom = 1
	# Unity CaptureBtn: BottomPanel center is 50px above the bottom, plus 45px child offset.
	nodes.capture_button.offset_left = -112
	nodes.capture_button.offset_top = -146
	nodes.capture_button.offset_right = 112
	nodes.capture_button.offset_bottom = -44


func _build_waiting_popup(parent: Control) -> Panel:
	var popup := Panel.new()
	popup.name = "ServerWaitingPopup"
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.z_index = 120
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup.offset_left = -450
	popup.offset_top = -160
	popup.offset_right = 450
	popup.offset_bottom = 160
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.88)
	style.border_color = Color.CYAN
	style.set_border_width_all(3)
	popup.add_theme_stylebox_override("panel", style)
	var text := Label.new()
	text.text = "⏳ 서버 연결 중입니다.\n잠시만 기다려주세요!"
	text.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	text.offset_left = 24
	text.offset_top = 24
	text.offset_right = -24
	text.offset_bottom = -24
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 48)
	text.add_theme_color_override("font_color", Color.WHITE)
	text.add_theme_color_override("font_outline_color", Color.BLACK)
	text.add_theme_constant_override("outline_size", 8)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_child(text)
	parent.add_child(popup)
	return popup
