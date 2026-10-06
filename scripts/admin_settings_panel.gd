extends PanelContainer

signal settings_changed
signal preview_changed(global_page: bool, background_index: int)
signal save_requested
signal close_requested
signal color_pick_requested
signal folder_requested
signal camera_settings_changed(camera_config: Dictionary)

const FIELDS := [
	["masterSensitivity", "키 민감도", 0, 100, 0.1], ["masterSmoothness", "경계 부드러움", 0, 50, 0.1],
	["masterSpillRemoval", "반사 제거", 0, 100, 0.1], ["masterLumaWeight", "밝기 가중치", 0, 100, 0.1],
	["masterEdgeChoke", "경계 축소", 0, 50, 0.1], ["masterPreBlur", "사전 흐림", 0, 100, 0.1],
	["zoom", "확대", 50, 300, 0.1], ["moveX", "좌우 이동", -100, 100, 0.1], ["moveY", "상하 이동", -100, 100, 0.1],
	["rotation", "회전", -180, 180, 0.1], ["brightness", "밝기", -100, 100, 0.1], ["contrast", "대비", 0, 200, 0.1],
	["saturation", "채도", 0, 200, 0.1], ["hue", "색조", -180, 180, 0.1],
	["cropTop", "위 크롭", 0, 1000, 1], ["cropBottom", "아래 크롭", 0, 1000, 1],
	["cropLeft", "왼쪽 크롭", 0, 1000, 1], ["cropRight", "오른쪽 크롭", 0, 1000, 1],
	["fadeX", "가로 페이드", 0, 500, 1], ["fadeY", "세로 페이드", 0, 500, 1],
]

var _config: Dictionary = {}
var _backgrounds: Array = []
var _global_page := true
var _background_index := 0
var _rows: Control
var _color_pick_button: Button
var _color_pick_active := false
var _resolution_option: OptionButton
var _fps_option: OptionButton
var _camera_name_input: LineEdit
var _default_camera_check: CheckBox
var _camera_status_label: Label

var preview_index: int:
	get:
		return _background_index

var is_global_page: bool:
	get:
		return _global_page


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_rows = Control.new()
	_rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_rows)
	_refresh()


func open_settings(config: Dictionary, backgrounds: Array) -> void:
	_config = config
	_backgrounds = backgrounds
	_global_page = true
	_background_index = clampi(_background_index, 0, maxi(0, backgrounds.size() - 1))
	visible = true
	_refresh()
	preview_changed.emit(_global_page, _background_index)


func _refresh() -> void:
	if _rows == null:
		return
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var background: Dictionary = _backgrounds[_background_index] if not _backgrounds.is_empty() else {}
	var global_data: Dictionary = _config.get("global", {})
	var title := Label.new()
	title.text = "[1] Global Chroma" if _global_page else "[2] BG %d/%d" % [_background_index + 1, _backgrounds.size()]
	title.position = Vector2(50, -2.5)
	title.size = Vector2(500, 35)
	title.add_theme_font_size_override("font_size", 26)
	_rows.add_child(title)
	var target_name := Label.new()
	target_name.text = "Global Master" if _global_page else str(background.get("bgName", ""))
	target_name.position = Vector2(50, 34)
	target_name.size = Vector2(500, 28)
	target_name.add_theme_font_size_override("font_size", 18)
	_rows.add_child(target_name)
	_add_button(_rows, "< PREV", Vector2(30, 1015), Vector2(160, 50), func() -> void: _step_page(-1))
	_add_button(_rows, "NEXT >", Vector2(1730, 1015), Vector2(160, 50), func() -> void: _step_page(1))
	_add_button(_rows, "↻ 0으로 초기화", Vector2(860, 960), Vector2(200, 40), _reset_page)
	_add_button(_rows, "SAVE", Vector2(870, 1015), Vector2(180, 50), func() -> void: save_requested.emit())
	_color_pick_button = _add_button(_rows, "스포이드 (색상 추출)", Vector2(175, 617.5), Vector2(250, 35), func() -> void: color_pick_requested.emit())
	set_color_pick_active(_color_pick_active)
	_add_button(_rows, "폴더 열기", Vector2(1710, 20), Vector2(120, 40), func() -> void: folder_requested.emit())
	if _global_page:
		_add_camera_controls()
	if _backgrounds.is_empty():
		return

	var color: Dictionary = background.get("color", {})
	var transform: Dictionary = background.get("transform", {})
	var crop: Dictionary = global_data.get("masterCrop", {}) if _global_page else background.get("crop", {})
	var global_positions := {
		"masterSensitivity": Vector2(72, 64), "masterSmoothness": Vector2(72, 114),
		"masterSpillRemoval": Vector2(72, 164), "masterEdgeChoke": Vector2(72, 214),
		"masterLumaWeight": Vector2(72, 264), "masterPreBlur": Vector2(72, 314),
		"cropTop": Vector2(572, 364), "cropBottom": Vector2(572, 414),
		"cropLeft": Vector2(572, 464), "cropRight": Vector2(572, 514),
		"fadeX": Vector2(572, 564), "fadeY": Vector2(572, 614),
	}
	var local_positions := {
		"masterSensitivity": Vector2(72, 64), "masterSmoothness": Vector2(72, 114),
		"masterSpillRemoval": Vector2(72, 164), "masterEdgeChoke": Vector2(72, 214),
		"masterLumaWeight": Vector2(72, 264), "masterPreBlur": Vector2(72, 314),
		"zoom": Vector2(572, 114), "moveX": Vector2(572, 164), "moveY": Vector2(572, 214), "rotation": Vector2(572, 264),
		"brightness": Vector2(72, 414), "contrast": Vector2(72, 464), "saturation": Vector2(72, 514), "hue": Vector2(72, 564),
	}
	var positions: Dictionary = global_positions if _global_page else local_positions
	for field in FIELDS:
		var key: String = field[0]
		var is_crop := key.begins_with("crop") or key in ["fadeX", "fadeY"]
		if is_crop and not _global_page:
			continue
		if not positions.has(key):
			continue
		_add_slider(field, global_data, background, color, transform, crop, positions[key])


func _add_camera_controls() -> void:
	var camera: Dictionary = _config.get("camera", {})
	var title := Label.new()
	title.text = "카메라 입력 품질"
	title.position = Vector2(1100, 65)
	title.size = Vector2(620, 32)
	title.add_theme_font_size_override("font_size", 22)
	_rows.add_child(title)
	_resolution_option = OptionButton.new()
	_resolution_option.position = Vector2(1100, 104)
	_resolution_option.size = Vector2(300, 46)
	for size in [Vector2i(3840, 2160), Vector2i(1920, 1080), Vector2i(1280, 720), Vector2i(640, 480)]:
		_resolution_option.add_item("%d × %d" % [size.x, size.y])
		_resolution_option.set_item_metadata(_resolution_option.item_count - 1, size)
	var requested_size := Vector2i(int(camera.get("requestedWidth", 1920)), int(camera.get("requestedHeight", 1080)))
	var selected_resolution := -1
	for i in range(_resolution_option.item_count):
		if _resolution_option.get_item_metadata(i) == requested_size:
			selected_resolution = i
			break
	if selected_resolution < 0:
		_resolution_option.add_item("사용자 지정 %d × %d" % [requested_size.x, requested_size.y])
		selected_resolution = _resolution_option.item_count - 1
	_resolution_option.select(selected_resolution)
	_rows.add_child(_resolution_option)
	_fps_option = OptionButton.new()
	_fps_option.position = Vector2(1415, 104)
	_fps_option.size = Vector2(125, 46)
	for rate in [15, 24, 30, 60]:
		_fps_option.add_item("%d fps" % rate)
		_fps_option.set_item_metadata(_fps_option.item_count - 1, rate)
	var requested_fps := int(camera.get("requestedFPS", 30))
	var selected_fps := -1
	for i in range(_fps_option.item_count):
		if int(_fps_option.get_item_metadata(i)) == requested_fps:
			selected_fps = i
			break
	if selected_fps < 0:
		_fps_option.add_item("%d fps" % requested_fps)
		selected_fps = _fps_option.item_count - 1
		_fps_option.set_item_metadata(selected_fps, requested_fps)
	_fps_option.select(selected_fps)
	_rows.add_child(_fps_option)
	_default_camera_check = CheckBox.new()
	_default_camera_check.text = "기본 장치"
	_default_camera_check.position = Vector2(1100, 158)
	_default_camera_check.size = Vector2(175, 42)
	_default_camera_check.button_pressed = bool(camera.get("useDefaultDevice", true))
	_default_camera_check.add_theme_font_size_override("font_size", 17)
	_rows.add_child(_default_camera_check)
	_camera_name_input = LineEdit.new()
	_camera_name_input.position = Vector2(1280, 160)
	_camera_name_input.size = Vector2(425, 40)
	_camera_name_input.placeholder_text = "장치명 일부 (예: Insta360)"
	_camera_name_input.text = str(camera.get("deviceName", ""))
	_camera_name_input.add_theme_font_size_override("font_size", 16)
	_rows.add_child(_camera_name_input)
	_camera_status_label = Label.new()
	_camera_status_label.position = Vector2(1100, 210)
	_camera_status_label.size = Vector2(610, 46)
	_camera_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_camera_status_label.add_theme_font_size_override("font_size", 16)
	_camera_status_label.text = "요청 %d×%d @ %d fps · 실제 입력 대기 중" % [requested_size.x, requested_size.y, requested_fps]
	_rows.add_child(_camera_status_label)
	_add_button(_rows, "품질 적용 · 재연결", Vector2(1515, 264), Vector2(210, 48), _apply_camera_settings)


func _apply_camera_settings() -> void:
	var camera: Dictionary = _config.get("camera", {}).duplicate(true)
	var size: Vector2i = _resolution_option.get_item_metadata(_resolution_option.selected)
	camera["requestedWidth"] = size.x
	camera["requestedHeight"] = size.y
	camera["requestedFPS"] = int(_fps_option.get_item_metadata(_fps_option.selected))
	camera["useDefaultDevice"] = _default_camera_check.button_pressed
	camera["deviceName"] = _camera_name_input.text.strip_edges()
	_config["camera"] = camera
	set_camera_status(0, 0, 0)
	camera_settings_changed.emit(camera)


func set_camera_status(actual_width: int, actual_height: int, actual_fps: int = 0) -> void:
	if _camera_status_label == null or not is_instance_valid(_camera_status_label):
		return
	var camera: Dictionary = _config.get("camera", {})
	var requested := "%d×%d @ %d fps" % [int(camera.get("requestedWidth", 1920)), int(camera.get("requestedHeight", 1080)), int(camera.get("requestedFPS", 30))]
	if actual_width <= 0 or actual_height <= 0:
		var waiting := "요청 %s · 실제 입력 대기 중" % requested
		if _camera_status_label.text != waiting:
			_camera_status_label.text = waiting
		return
	var actual := "%d×%d" % [actual_width, actual_height]
	if actual_fps > 0:
		actual += " @ %d fps" % actual_fps
	var reduced := actual_width < int(camera.get("requestedWidth", 1920)) or actual_height < int(camera.get("requestedHeight", 1080)) or (actual_fps > 0 and actual_fps < int(camera.get("requestedFPS", 30)))
	var status_text := "요청 %s · 실제 %s%s" % [requested, actual, " (장치 제한)" if reduced else ""]
	if _camera_status_label.text != status_text:
		_camera_status_label.text = status_text


func _add_slider(field: Array, global_data: Dictionary, background: Dictionary, color: Dictionary, transform: Dictionary, crop: Dictionary, position: Vector2) -> void:
	var key: String = field[0]
	var row := HBoxContainer.new()
	row.position = position
	row.size = Vector2(456, 42)
	var label := Label.new()
	label.text = field[1]
	label.custom_minimum_size.x = 110
	label.custom_minimum_size.y = 42
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = field[2]
	slider.max_value = field[3]
	slider.step = field[4]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 42
	slider.value = _read_value(key, global_data, color, transform, crop)
	slider.value_changed.connect(_write_value.bind(key, global_data, background, color, transform, crop))
	row.add_child(slider)
	_rows.add_child(row)


func _write_value(value: float, key: String, global_data: Dictionary, background: Dictionary, color: Dictionary, transform: Dictionary, crop: Dictionary) -> void:
	if key.begins_with("master"):
		global_data[key] = value
	elif key.begins_with("crop"):
		crop[key.trim_prefix("crop").to_lower()] = int(value)
	elif key in ["fadeX", "fadeY"]:
		crop[key] = int(value)
	elif key in ["zoom", "moveX", "moveY", "rotation"]:
		transform[key] = value
	else:
		color[key] = value
	if _global_page:
		_config["global"] = global_data
	else:
		background["color"] = color
		background["transform"] = transform
		background["crop"] = crop
		_backgrounds[_background_index] = background
	settings_changed.emit()


func _read_value(key: String, global_data: Dictionary, color: Dictionary, transform: Dictionary, crop: Dictionary) -> float:
	if key.begins_with("master"):
		return float(global_data.get(key, 0))
	if key.begins_with("crop"):
		return float(crop.get(key.trim_prefix("crop").to_lower(), 0))
	if key in ["fadeX", "fadeY"]:
		return float(crop.get(key, 0))
	if key in ["zoom", "moveX", "moveY", "rotation"]:
		return float(transform.get(key, 100 if key == "zoom" else 0))
	return float(color.get(key, 0 if key in ["brightness", "hue"] else 100))


func _step_page(direction: int) -> void:
	if _backgrounds.is_empty():
		return
	if _global_page:
		if direction < 0:
			return
		_global_page = false
		_background_index = 0
	elif direction < 0 and _background_index == 0:
		_global_page = true
	else:
		_background_index = posmod(_background_index + direction, _backgrounds.size())
	_refresh()
	preview_changed.emit(_global_page, _background_index)


func _reset_page() -> void:
	if _global_page:
		var global_data: Dictionary = _config.get("global", {})
		global_data["targetColor"] = "#00B140"
		for key in ["masterSensitivity", "masterSmoothness", "masterSpillRemoval", "masterLumaWeight", "masterEdgeChoke", "masterPreBlur"]:
			global_data[key] = 0.0
		_config["global"] = global_data
	else:
		var background: Dictionary = _backgrounds[_background_index]
		background["chroma"] = {
			"useLocalChroma": true, "localTargetColor": "#00B140", "localSensitivity": 0.0,
			"localSmoothness": 0.0, "localSpillRemoval": 0.0, "localLumaWeight": 0.0,
			"localEdgeChoke": 0.0, "localPreBlur": 0.0,
		}
		background["transform"] = {"zoom": 100.0, "moveX": 0.0, "moveY": 0.0, "rotation": 0.0}
		background["color"] = {"brightness": 0.0, "contrast": 100.0, "saturation": 100.0, "hue": 0.0}
		background["crop"] = {"top": 0, "bottom": 0, "left": 0, "right": 0, "fadeX": 0, "fadeY": 0}
		_backgrounds[_background_index] = background
	_refresh()
	settings_changed.emit()


func set_color_pick_active(active: bool) -> void:
	_color_pick_active = active
	if _color_pick_button == null:
		return
	_color_pick_button.text = "추출 중... (웹캠 클릭)" if active else "스포이드 (색상 추출)"
	var font_color := Color(1.0, 0.4, 0.4, 1.0) if active else Color(0.2, 0.2, 0.2, 1.0)
	_color_pick_button.add_theme_color_override("font_color", font_color)
	_color_pick_button.add_theme_color_override("font_hover_color", font_color)
	_color_pick_button.add_theme_color_override("font_pressed_color", font_color)


func _add_button(parent: Control, caption: String, position: Vector2, button_size: Vector2, callback: Callable) -> Button:
	var button := Button.new()
	button.text = caption
	button.position = position
	button.size = button_size
	button.add_theme_font_size_override("font_size", 18)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.92, 0.92, 0.92, 1.0)
	normal.border_color = Color(0.55, 0.55, 0.55, 1.0)
	normal.set_border_width_all(1)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.96, 0.96, 0.96, 1.0)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.78, 0.78, 0.78, 1.0)
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2, 1.0))
	button.add_theme_color_override("font_hover_color", Color(0.2, 0.2, 0.2, 1.0))
	button.add_theme_color_override("font_pressed_color", Color(0.2, 0.2, 0.2, 1.0))
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
