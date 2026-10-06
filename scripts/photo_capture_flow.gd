extends Node

signal state_requested(state: int)
signal status_changed(message: String)
signal photo_saved(file_name: String)

const State = preload("res://scripts/booth_state.gd").Value

var _controls: Dictionary = {}
var _photo_library: Node
var _photo_sharing: Node
var _running := false
var _ticket := 0


func configure(controls: Dictionary, photo_library: Node, photo_sharing: Node) -> void:
	_controls = controls
	_photo_library = photo_library
	_photo_sharing = photo_sharing


func is_running() -> bool:
	return _running


func start(seconds: int, background_name: String) -> void:
	if _running:
		return
	_running = true
	_ticket += 1
	var current_ticket := _ticket
	_controls.capture_button.disabled = true
	_controls.capture_button.visible = false
	state_requested.emit(State.PROCESSING)
	_countdown(seconds, current_ticket, background_name)


func cancel() -> void:
	_ticket += 1
	_running = false
	if _controls.is_empty():
		return
	_controls.timer_label.text = ""
	_controls.capture_button.disabled = false


func _is_current(ticket: int) -> bool:
	return _running and ticket == _ticket


func _countdown(remaining: int, ticket: int, background_name: String) -> void:
	if not _is_current(ticket):
		return
	if remaining <= 0:
		_controls.timer_label.text = ""
		await get_tree().process_frame
		if _is_current(ticket):
			_save_capture(ticket, background_name)
		return
	_controls.timer_label.text = str(remaining)
	_controls.timer_label.add_theme_color_override("font_color", Color("#ff5353") if remaining == 1 else (Color("#ffeb3b") if remaining <= 3 else Color("#66fcf1")))
	var tween := create_tween()
	_controls.timer_label.scale = Vector2.ONE * 1.5
	tween.tween_property(_controls.timer_label, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.0).timeout
	if _is_current(ticket):
		_countdown(remaining - 1, ticket, background_name)


func _save_capture(ticket: int, background_name: String) -> void:
	_controls.ui_layer.visible = false
	await get_tree().process_frame
	if not _is_current(ticket):
		_controls.ui_layer.visible = true
		return
	var image := _capture_viewport_image()
	if image == null or image.is_empty():
		_fail_capture(ticket, "사진 캡처 실패")
		return
	var file_name: String = _photo_library.save_photo(image, background_name)
	if file_name.is_empty():
		_fail_capture(ticket, "JPG 저장 실패")
		return
	_controls.result_preview.texture = ImageTexture.create_from_image(image)
	photo_saved.emit(file_name)
	_flash()
	await get_tree().create_timer(0.5).timeout
	if not _is_current(ticket):
		_controls.ui_layer.visible = true
		return
	_running = false
	_photo_sharing.share_photo(file_name)
	status_changed.emit("사진 저장 완료: " + file_name)
	state_requested.emit(State.RESULT)


func _fail_capture(ticket: int, message: String) -> void:
	if not _is_current(ticket):
		return
	_running = false
	status_changed.emit(message)
	state_requested.emit(State.CAPTURE)


func _capture_viewport_image() -> Image:
	var viewport_texture := get_viewport().get_texture()
	if viewport_texture == null:
		return null
	return viewport_texture.get_image()


func _flash() -> void:
	var flash: ColorRect = _controls.capture_flash
	flash.visible = true
	flash.color = Color(1, 1, 1, 0.9)
	var tween := create_tween()
	tween.tween_property(flash, "color:a", 0.0, 0.5)
	tween.tween_callback(func() -> void: flash.visible = false)
