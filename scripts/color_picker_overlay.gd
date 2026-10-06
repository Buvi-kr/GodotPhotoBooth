extends Node

signal color_picked(color: Color)
signal status_changed(message: String)
signal active_changed(active: bool)

const INVALID_UV := Vector2(-1.0, -1.0)

var camera_view: TextureRect
var admin_panel: Node
var camera_image: Image
var camera_texture: Texture2D
var active := false
var panel: Panel
var preview: TextureRect
var magnifier_material: ShaderMaterial


func configure(source_view: TextureRect, settings_panel: Node) -> void:
	camera_view = source_view
	admin_panel = settings_panel
	_build_overlay()


func set_camera_frame(image: Image, texture: Texture2D) -> void:
	camera_image = image
	camera_texture = texture
	if active:
		_update_preview(get_viewport().get_mouse_position())


func handle_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseMotion:
		_update_preview(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_pick(event.position)


func is_active() -> bool:
	return active


func activate() -> void:
	if active:
		return
	active = true
	admin_panel.set_color_pick_active(true)
	active_changed.emit(true)
	status_changed.emit("웹캠 프레임을 눌러 키 색상을 추출하세요 · ESC 취소")
	_update_preview(get_viewport().get_mouse_position())


func cancel() -> void:
	if not active:
		return
	active = false
	panel.visible = false
	admin_panel.set_color_pick_active(false)
	active_changed.emit(false)
	status_changed.emit("스포이드 취소")


func _build_overlay() -> void:
	panel = Panel.new()
	panel.size = Vector2(150, 150)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 100
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color.WHITE
	frame.border_color = Color(0.35, 0.35, 0.35, 1.0)
	frame.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", frame)
	preview = TextureRect.new()
	preview.position = Vector2(5, 5)
	preview.size = Vector2(140, 140)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	magnifier_material = ShaderMaterial.new()
	magnifier_material.shader = load("res://shaders/color_magnifier.gdshader")
	preview.material = magnifier_material
	panel.add_child(preview)
	var crosshair := ColorRect.new()
	crosshair.position = Vector2(70, 70)
	crosshair.size = Vector2(10, 10)
	crosshair.color = Color.RED
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(crosshair)
	get_parent().add_child(panel)


func _camera_uv_at(screen_position: Vector2) -> Vector2:
	if camera_image == null or camera_image.is_empty() or camera_view.size.x <= 0.0 or camera_view.size.y <= 0.0:
		return INVALID_UV
	var local_position := camera_view.make_canvas_position_local(screen_position)
	if local_position.x < 0.0 or local_position.y < 0.0 or local_position.x > camera_view.size.x or local_position.y > camera_view.size.y:
		return INVALID_UV
	var uv := local_position / camera_view.size
	var image_aspect := float(camera_image.get_width()) / maxf(float(camera_image.get_height()), 1.0)
	var view_aspect := camera_view.size.x / camera_view.size.y
	if image_aspect > view_aspect:
		var visible_width := view_aspect / image_aspect
		uv.x = (uv.x - (1.0 - visible_width) * 0.5) / visible_width
	else:
		var visible_height := image_aspect / view_aspect
		uv.y = (uv.y - (1.0 - visible_height) * 0.5) / visible_height
	return uv


func _update_preview(screen_position: Vector2) -> void:
	if not active or camera_image == null or camera_image.is_empty():
		panel.visible = false
		return
	var uv := _camera_uv_at(screen_position)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		panel.visible = false
		return
	preview.texture = camera_texture
	magnifier_material.set_shader_parameter("focus_uv", uv)
	var viewport_size := get_viewport().get_visible_rect().size
	panel.position = Vector2(screen_position.x + 100.0, screen_position.y - 100.0)
	panel.position.x = clampf(panel.position.x, 0.0, maxf(0.0, viewport_size.x - panel.size.x))
	panel.position.y = clampf(panel.position.y, 0.0, maxf(0.0, viewport_size.y - panel.size.y))
	panel.visible = true


func _pick(screen_position: Vector2) -> void:
	active = false
	panel.visible = false
	admin_panel.set_color_pick_active(false)
	active_changed.emit(false)
	if camera_image == null or camera_image.is_empty():
		status_changed.emit("웹캠 프레임 없음")
		return
	var uv := _camera_uv_at(screen_position)
	if uv.x < 0.0 or uv.y < 0.0 or uv.x > 1.0 or uv.y > 1.0:
		status_changed.emit("웹캠 영역 밖 클릭 · 스포이드 취소")
		return
	var px := clampi(floori(uv.x * camera_image.get_width()), 0, camera_image.get_width() - 1)
	var py := clampi(floori(uv.y * camera_image.get_height()), 0, camera_image.get_height() - 1)
	var sampled: Color = camera_image.get_pixel(px, py)
	color_picked.emit(sampled)
