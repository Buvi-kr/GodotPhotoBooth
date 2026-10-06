extends Control

const CameraFeedScript = preload("res://scripts/camera_feed.gd")
const PhotoLibraryScript = preload("res://scripts/photo_library.gd")
const PhotoSharingScript = preload("res://scripts/photo_sharing.gd")
const ColorPickerOverlayScript = preload("res://scripts/color_picker_overlay.gd")
const BoothUIFactoryScript = preload("res://scripts/booth_ui_factory.gd")
const BoothConfigStoreScript = preload("res://scripts/booth_config_store.gd")
const ChromaSettingsApplierScript = preload("res://scripts/chroma_settings_applier.gd")
const BoothStateDefinitionScript = preload("res://scripts/booth_state.gd")
const BoothStatePresenterScript = preload("res://scripts/booth_state_presenter.gd")
const PhotoCaptureFlowScript = preload("res://scripts/photo_capture_flow.gd")
const BoothState = BoothStateDefinitionScript.Value
const CAPTURE_SECONDS = 8
const IDLE_TIME_LIMIT := 60.0
const STANDBY_BLINK_INTERVAL := 0.2
const SERVER_WAITING_POPUP_SECONDS := 3.0
const NAVIGATION_COOLDOWN_SECONDS := 0.25
const STANDBY_INPUT_COOLDOWN_MS := 500
const STATE_CHANGE_COOLDOWN_MS := 400
const INPUT_TRIGGER_COOLDOWN_MS := 300

var config: Dictionary = {}
var backgrounds: Array = []
var selected_index = 0
var state = BoothState.STANDBY
var idle_seconds = 0.0
var standby_blink_elapsed := 0.0
var standby_blink_visible := true
var cursor_index = 0
var result_index = 0
var navigation_cooldown := 0.0
var standby_input_ready_ms := 0
var keyboard_navigation_step := 0
var state_change_ready_ms := 0
var input_trigger_ready_ms := 0
var state_initialized := false
var camera_texture: ImageTexture
var raw_camera_image: Image
var camera_ready := false
var camera_actual_fps := 0
var _camera_fps_window_started_ms := 0
var _camera_fps_frame_count := 0
var texture_cache: Dictionary = {}
var last_photo_name = ""
var photos_dir = ""
var camera_feed
var photo_library
var photo_sharing
var booth_ui_factory
var config_store
var chroma_settings_applier
var booth_state_presenter
var photo_capture_flow
var ui_controls: Dictionary = {}
var chroma_material: ShaderMaterial
var capture_keyboard_ready_ms := 0
var selection_pending = false
var idle_timer: Timer
var bg_view: TextureRect
var cam_view: TextureRect
var front_view: TextureRect
var prompt: Label
var timer_label: Label
var status: Label
var bg_buttons: GridContainer
var ui_layer: Control
var result_panel: Control
var result_background_view: TextureRect
var result_preview: TextureRect
var qr_view: TextureRect
var admin_panel
var color_picker
var server_waiting_popup: Panel
var server_waiting_timer: Timer
var capture_button: Button
var navigation_cursor: Panel
var navigation_cursor_target_position := Vector2.ZERO
var navigation_cursor_target_size := Vector2.ZERO
var standby_video: VideoStreamPlayer
var select_video: VideoStreamPlayer
var transition_video_stream: VideoStream
var transition_in_progress := false
var transition_timer: Timer

func _ready():
	photos_dir = ProjectSettings.globalize_path("res://MyPhotoBooth") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("MyPhotoBooth")
	config_store = BoothConfigStoreScript.new()
	chroma_settings_applier = ChromaSettingsApplierScript.new()
	photo_library = PhotoLibraryScript.new()
	add_child(photo_library)
	photo_library.configure(photos_dir)
	camera_feed = CameraFeedScript.new(); camera_feed.frame_received.connect(_on_camera_frame); camera_feed.status_changed.connect(_set_status); add_child(camera_feed)
	photo_sharing = PhotoSharingScript.new(); photo_sharing.status_changed.connect(_set_status); photo_sharing.qr_ready.connect(_on_qr_ready); photo_sharing.page_visited.connect(photo_library.mark_page_visited); photo_sharing.photo_downloaded.connect(photo_library.mark_downloaded); add_child(photo_sharing)
	_build_ui()
	_load_config()
	_build_background_buttons()
	_apply_background()
	_start_camera()
	_start_sharing()
	_show_state(BoothState.STANDBY)

func _build_ui():
	booth_ui_factory = BoothUIFactoryScript.new()
	var controls: Dictionary = booth_ui_factory.build(self, {
		"capture": _begin_capture,
		"retake": _retake,
		"home": _home,
		"transition_finished": _on_transition_finished,
	})
	ui_controls = controls
	booth_state_presenter = BoothStatePresenterScript.new()
	bg_view = controls.bg_view
	cam_view = controls.cam_view
	front_view = controls.front_view
	chroma_material = controls.chroma_material
	camera_texture = controls.camera_texture
	standby_video = controls.standby_video
	select_video = controls.select_video
	transition_video_stream = controls.transition_video_stream
	transition_timer = controls.transition_timer
	ui_layer = controls.ui_layer
	prompt = controls.prompt
	navigation_cursor = controls.navigation_cursor
	timer_label = controls.timer_label
	bg_buttons = controls.bg_buttons
	result_panel = controls.result_panel
	result_background_view = controls.result_background_view
	result_preview = controls.result_preview
	qr_view = controls.qr_view
	status = controls.status
	capture_button = controls.capture_button
	admin_panel = controls.admin_panel
	server_waiting_popup = controls.server_waiting_popup
	admin_panel.settings_changed.connect(_apply_background)
	admin_panel.camera_settings_changed.connect(_restart_camera)
	admin_panel.preview_changed.connect(_on_admin_preview_changed)
	admin_panel.save_requested.connect(_save_config)
	admin_panel.close_requested.connect(func(): _show_state(BoothState.STANDBY))
	admin_panel.color_pick_requested.connect(_arm_picker)
	admin_panel.folder_requested.connect(_open_asset_folder)
	color_picker = ColorPickerOverlayScript.new()
	add_child(color_picker)
	color_picker.configure(cam_view, admin_panel)
	color_picker.color_picked.connect(_on_color_picked)
	color_picker.status_changed.connect(_set_status)
	photo_capture_flow = PhotoCaptureFlowScript.new()
	add_child(photo_capture_flow)
	photo_capture_flow.configure(ui_controls, photo_library, photo_sharing)
	photo_capture_flow.state_requested.connect(_show_state)
	photo_capture_flow.status_changed.connect(_set_status)
	photo_capture_flow.photo_saved.connect(_on_photo_saved)
	idle_timer = Timer.new(); idle_timer.wait_time = 1.0; idle_timer.timeout.connect(_idle_tick); add_child(idle_timer); idle_timer.start()
	server_waiting_timer = Timer.new(); server_waiting_timer.one_shot = true; server_waiting_timer.wait_time = SERVER_WAITING_POPUP_SECONDS; server_waiting_timer.timeout.connect(_dismiss_server_waiting_popup); add_child(server_waiting_timer)


func _open_asset_folder() -> void:
	var folder := OS.get_executable_path().get_base_dir().path_join("StreamingAssets")
	if OS.has_feature("editor"):
		folder = ProjectSettings.globalize_path("res://data")
	OS.shell_open(folder)

func _on_transition_finished() -> void:
	if transition_in_progress:
		transition_in_progress = false
		_show_state(BoothState.SELECT_BG)

func _process(_delta):
	navigation_cooldown = maxf(0.0, navigation_cooldown - _delta)
	if state == BoothState.STANDBY:
		standby_blink_elapsed += _delta
		if standby_blink_elapsed >= STANDBY_BLINK_INTERVAL:
			standby_blink_elapsed = fposmod(standby_blink_elapsed, STANDBY_BLINK_INTERVAL)
			standby_blink_visible = not standby_blink_visible
			prompt.visible = standby_blink_visible
	if navigation_cursor.visible:
		navigation_cursor.global_position = navigation_cursor.global_position.lerp(navigation_cursor_target_position, minf(_delta * 15.0, 1.0))
		navigation_cursor.size = navigation_cursor.size.lerp(navigation_cursor_target_size, minf(_delta * 15.0, 1.0))
		navigation_cursor.modulate.a = 0.4 + 0.6 * absf(sin(Time.get_ticks_msec() / 500.0))
	if state in [BoothState.SELECT_BG, BoothState.RESULT]:
		var step := _navigation_step()
		if step != 0 and navigation_cooldown <= 0.0:
			navigation_cooldown = NAVIGATION_COOLDOWN_SECONDS
			if state == BoothState.SELECT_BG: cursor_index = posmod(cursor_index + step, max(1, backgrounds.size())); _select_background(cursor_index)
			else: result_index = posmod(result_index + step, 2); _update_navigation_cursor()
	if state in [BoothState.STANDBY, BoothState.SELECT_BG, BoothState.CAPTURE, BoothState.RESULT] and (Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_select")) and _consume_input_trigger():
		match state:
			BoothState.STANDBY: _begin_transition()
			BoothState.SELECT_BG: _choose_background(cursor_index)
			BoothState.CAPTURE:
				if Time.get_ticks_msec() >= capture_keyboard_ready_ms: _begin_capture()
			BoothState.RESULT: _do_result_action()

func _input(event: InputEvent):
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton or event is InputEventScreenTouch:
		if event.is_pressed():
			idle_seconds = 0.0
			if server_waiting_popup != null and server_waiting_popup.visible: _dismiss_server_waiting_popup()
			if state == BoothState.STANDBY and not event is InputEventKey: _begin_transition()
	if event is InputEventKey and event.pressed and not event.echo and state in [BoothState.SELECT_BG, BoothState.RESULT]:
		if event.keycode in [KEY_RIGHT, KEY_DOWN, KEY_D, KEY_S]: keyboard_navigation_step = 1
		elif event.keycode in [KEY_LEFT, KEY_UP, KEY_A, KEY_W]: keyboard_navigation_step = -1


func _navigation_step() -> int:
	var keyboard_step := keyboard_navigation_step
	keyboard_navigation_step = 0
	var horizontal := Input.get_axis("ui_left", "ui_right")
	var vertical := Input.get_axis("ui_up", "ui_down")
	if absf(horizontal) > 0.5 or absf(vertical) > 0.5:
		return 1 if horizontal > 0.0 or vertical > 0.0 else -1
	var right_pressed := Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("ui_down")
	var left_pressed := Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_up")
	if right_pressed:
		return 1
	if left_pressed:
		return -1
	return keyboard_step


func _consume_input_trigger() -> bool:
	var now := Time.get_ticks_msec()
	if now < input_trigger_ready_ms:
		return false
	input_trigger_ready_ms = now + INPUT_TRIGGER_COOLDOWN_MS
	return true

func _unhandled_input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.alt_pressed and event.keycode == KEY_S: _show_state(BoothState.STANDBY if state == BoothState.CALIBRATION else BoothState.CALIBRATION)
		elif event.keycode == KEY_ESCAPE:
			if _consume_input_trigger():
				if color_picker.is_active(): color_picker.cancel()
				elif state in [BoothState.CAPTURE, BoothState.RESULT]: _show_state(BoothState.SELECT_BG)
				else: _home()
		elif state == BoothState.STANDBY:
			if event.keycode not in [KEY_CTRL, KEY_ALT] and not event.ctrl_pressed and not event.alt_pressed and _consume_input_trigger():
				_begin_transition()
		elif state == BoothState.SELECT_BG and event.keycode >= KEY_1 and event.keycode <= KEY_9 and _consume_input_trigger(): _choose_background(event.keycode - KEY_1)
		elif state == BoothState.SELECT_BG and event.keycode >= KEY_KP_1 and event.keycode <= KEY_KP_9 and _consume_input_trigger(): _choose_background(event.keycode - KEY_KP_1)
		elif state == BoothState.CALIBRATION and event.keycode == KEY_F5: _reload_config()
	color_picker.handle_input(event)

func _show_state(next_state: BoothState):
	var now := Time.get_ticks_msec()
	var changed: bool = state != next_state
	if state_initialized and changed and now < state_change_ready_ms:
		return
	if not state_initialized or changed:
		state_initialized = true
		state_change_ready_ms = now + STATE_CHANGE_COOLDOWN_MS
	if ui_layer != null:
		ui_layer.visible = true
	if next_state == BoothState.CAPTURE and state != BoothState.CAPTURE:
		capture_keyboard_ready_ms = Time.get_ticks_msec() + 1000
	if next_state != BoothState.CALIBRATION and color_picker.is_active():
		color_picker.cancel()
	if state in [BoothState.CAPTURE, BoothState.PROCESSING] and next_state not in [BoothState.CAPTURE, BoothState.PROCESSING]:
		photo_capture_flow.cancel()
	state = next_state
	transition_in_progress = false
	transition_timer.stop()
	idle_seconds = 0.0
	if state == BoothState.STANDBY:
		standby_blink_elapsed = 0.0
		standby_blink_visible = true
		standby_input_ready_ms = Time.get_ticks_msec() + STANDBY_INPUT_COOLDOWN_MS
	if state == BoothState.SELECT_BG:
		cursor_index = 0
	booth_state_presenter.apply(state, ui_controls, state == BoothState.CALIBRATION and not admin_panel.is_global_page)
	if state == BoothState.STANDBY: bg_view.texture = null; front_view.texture = null
	elif state == BoothState.SELECT_BG: _select_background(cursor_index)
	elif state == BoothState.CAPTURE: _apply_background(); capture_button.disabled = false
	elif state == BoothState.CALIBRATION:
		admin_panel.open_settings(config, backgrounds)
		if raw_camera_image != null:
			admin_panel.set_camera_status(raw_camera_image.get_width(), raw_camera_image.get_height(), camera_actual_fps)
	elif state == BoothState.RESULT: result_index = 0
	if state in [BoothState.SELECT_BG, BoothState.RESULT]:
		_update_navigation_cursor.call_deferred()

func _begin_transition() -> void:
	if transition_in_progress or state != BoothState.STANDBY or Time.get_ticks_msec() < standby_input_ready_ms:
		return
	if transition_video_stream == null:
		_show_state(BoothState.SELECT_BG)
		return
	transition_in_progress = true
	prompt.visible = false
	standby_video.stream = transition_video_stream
	standby_video.loop = false
	standby_video.play()
	transition_timer.start()

func _load_config():
	var loaded: Dictionary = config_store.load_config()
	config = loaded.config
	backgrounds = config.get("backgrounds", [])
	if not loaded.ok:
		status.text = loaded.message
		return
	_apply_chroma()
	status.text = "%d개 배경 설정을 읽었습니다" % backgrounds.size()

func _save_config():
	if not config_store.save_config(config):
		status.text = "설정 저장 실패"
		return
	_apply_chroma()
	status.text = "설정 저장 완료"

func _reload_config():
	var camera_before: Dictionary = config.get("camera", {}).duplicate(true)
	_load_config()
	_build_background_buttons()
	_apply_background()
	if camera_before != config.get("camera", {}):
		await _restart_camera(config.get("camera", {}))
	if state == BoothState.CALIBRATION:
		admin_panel.open_settings(config, backgrounds)
		if raw_camera_image != null:
			admin_panel.set_camera_status(raw_camera_image.get_width(), raw_camera_image.get_height(), camera_actual_fps)

func _build_background_buttons():
	for c in bg_buttons.get_children(): c.queue_free()
	for i in range(backgrounds.size()):
		var bg: Dictionary = backgrounds[i]
		var btn = booth_ui_factory.create_button(str(bg.get("bgName", i + 1)), _choose_background.bind(i))
		btn.custom_minimum_size = Vector2(580, 326)
		btn.icon = _find_texture(str(bg.get("bgName", "")) + "_thumbnail")
		if btn.icon == null: btn.icon = _find_texture(str(bg.get("bgName", "")))
		if btn.icon != null: btn.text = ""
		btn.expand_icon = true
		bg_buttons.add_child(btn)

func _choose_background(index: int):
	if selection_pending or index < 0 or index >= backgrounds.size(): return
	cursor_index = index; _select_background(index)
	selection_pending = true
	await get_tree().create_timer(0.8).timeout
	selection_pending = false
	_show_state(BoothState.CAPTURE)

func _select_background(index: int):
	if backgrounds.is_empty(): return
	selected_index = clampi(index, 0, backgrounds.size() - 1); _apply_background()
	if state == BoothState.SELECT_BG: _update_navigation_cursor()


func _update_navigation_cursor() -> void:
	if navigation_cursor == null:
		return
	var target: Control
	if state == BoothState.SELECT_BG and cursor_index >= 0 and cursor_index < bg_buttons.get_child_count():
		target = bg_buttons.get_child(cursor_index) as Control
	elif state == BoothState.RESULT:
		var actions := result_panel.get_child(3) as VBoxContainer
		if result_index >= 0 and result_index < actions.get_child_count():
			target = actions.get_child(result_index) as Control
	if target == null:
		navigation_cursor.visible = false
		return
	var rect := target.get_global_rect()
	var padding := Vector2(8.0, 8.0)
	navigation_cursor_target_position = rect.position - padding
	navigation_cursor_target_size = rect.size + padding * 2.0
	if not navigation_cursor.visible:
		navigation_cursor.global_position = navigation_cursor_target_position
		navigation_cursor.size = navigation_cursor_target_size
	navigation_cursor.visible = true
	navigation_cursor.move_to_front()
	if state == BoothState.SELECT_BG:
		prompt.move_to_front()

func _on_admin_preview_changed(global_page: bool, background_index: int) -> void:
	if state != BoothState.CALIBRATION:
		return
	bg_view.visible = not global_page
	front_view.visible = not global_page
	if not global_page and background_index >= 0 and background_index < backgrounds.size():
		_apply_background(background_index)
	else:
		_apply_background()


func _active_background_index() -> int:
	if state == BoothState.CALIBRATION and admin_panel != null and not admin_panel.is_global_page:
		return admin_panel.preview_index
	return selected_index


func _apply_background(index: int = -1):
	if backgrounds.is_empty(): return
	if state == BoothState.CALIBRATION and admin_panel.is_global_page:
		cam_view.pivot_offset = cam_view.size * 0.5
		cam_view.scale = Vector2.ONE
		cam_view.rotation_degrees = 0.0
		cam_view.position = Vector2.ZERO
		_apply_chroma(selected_index, true)
		return
	var active_index := index if index >= 0 and index < backgrounds.size() else _active_background_index()
	active_index = clampi(active_index, 0, backgrounds.size() - 1)
	var bg: Dictionary = backgrounds[active_index]; var name = str(bg.get("bgName", ""))
	bg_view.texture = _find_texture(name); front_view.texture = _find_texture(name + "_front"); _apply_chroma(active_index)
	var tr: Dictionary = bg.get("transform", {}); var zoom = float(tr.get("zoom", 100.0)); if zoom <= 5.0: zoom *= 100.0
	var move_x := float(tr.get("moveX", 0)); var move_y := float(tr.get("moveY", 0))
	if absf(move_x) <= 1.0 and move_x != 0.0: move_x *= 100.0
	if absf(move_y) <= 1.0 and move_y != 0.0: move_y *= 100.0
	cam_view.pivot_offset = cam_view.size * 0.5; cam_view.scale = Vector2.ONE * maxf(zoom / 100.0, 0.01); cam_view.rotation_degrees = float(tr.get("rotation", 0.0)); cam_view.position = Vector2(move_x * 10.0, -move_y * 10.0)

func _find_texture(name: String) -> Texture2D:
	if texture_cache.has(name): return texture_cache[name]
	for ext in ["png", "jpg", "jpeg"]:
		var path = "res://assets/backgrounds/%s.%s" % [name, ext]
		if ResourceLoader.exists(path): texture_cache[name] = load(path); return texture_cache[name]
		path = OS.get_executable_path().get_base_dir().path_join("StreamingAssets/%s.%s" % [name, ext])
		if FileAccess.file_exists(path):
			var image = Image.load_from_file(path)
			if image:
				texture_cache[name] = ImageTexture.create_from_image(image)
				return texture_cache[name]
	texture_cache[name] = null
	return null

func _apply_chroma(index: int = -1, neutral_grading: bool = false):
	if chroma_material == null or config.is_empty():
		return
	var active_index := index if index >= 0 and index < backgrounds.size() else _active_background_index()
	chroma_settings_applier.apply(chroma_material, config, backgrounds, raw_camera_image, active_index, neutral_grading)

func _start_camera():
	var helper := OS.get_executable_path().get_base_dir().path_join("CameraBridge/CameraBridge.exe")
	if OS.has_feature("editor") or not FileAccess.file_exists(helper):
		helper = ProjectSettings.globalize_path("res://bin/camera-bridge/CameraBridge.exe")
	_camera_fps_window_started_ms = 0
	_camera_fps_frame_count = 0
	camera_actual_fps = 0
	camera_feed.start(config.get("camera", {}), helper)


func _restart_camera(camera_config: Dictionary) -> void:
	config["camera"] = camera_config.duplicate(true)
	camera_ready = false
	camera_actual_fps = 0
	_camera_fps_window_started_ms = 0
	_camera_fps_frame_count = 0
	status.text = "카메라 설정 적용 중 · 브리지 재연결"
	var helper := OS.get_executable_path().get_base_dir().path_join("CameraBridge/CameraBridge.exe")
	if OS.has_feature("editor") or not FileAccess.file_exists(helper):
		helper = ProjectSettings.globalize_path("res://bin/camera-bridge/CameraBridge.exe")
	camera_feed.stop()
	await get_tree().create_timer(0.75).timeout
	camera_feed.start(config.get("camera", {}), helper)


func _on_camera_frame(image: Image) -> void:
	raw_camera_image = image
	camera_ready = true
	var now := Time.get_ticks_msec()
	_camera_fps_frame_count += 1
	if _camera_fps_window_started_ms == 0:
		_camera_fps_window_started_ms = now
	elif now - _camera_fps_window_started_ms >= 1000:
		camera_actual_fps = roundi(float(_camera_fps_frame_count) * 1000.0 / float(now - _camera_fps_window_started_ms))
		_camera_fps_frame_count = 0
		_camera_fps_window_started_ms = now
	_update_camera_viewport(image)
	if camera_texture == null or camera_texture.get_width() != image.get_width() or camera_texture.get_height() != image.get_height():
		camera_texture = ImageTexture.create_from_image(image)
		cam_view.texture = camera_texture
		chroma_material.set_shader_parameter("source_texture", camera_texture)
	else:
		camera_texture.update(image)
	color_picker.set_camera_frame(image, camera_texture)
	if state == BoothState.CALIBRATION:
		admin_panel.set_camera_status(image.get_width(), image.get_height(), camera_actual_fps)


func _update_camera_viewport(image: Image) -> void:
	var camera_config: Dictionary = config.get("camera", {})
	var orientation := str(camera_config.get("orientationOverride", "auto")).to_lower()
	var portrait := orientation == "portrait" or (orientation == "auto" and image.get_width() < image.get_height())
	if portrait:
		var viewport_size := get_viewport_rect().size
		var portrait_width := viewport_size.y * float(image.get_width()) / maxf(float(image.get_height()), 1.0)
		var left := -portrait_width * 0.5
		var right := portrait_width * 0.5
		if cam_view.anchor_left != 0.5 or cam_view.anchor_right != 0.5 or cam_view.anchor_top != 0.0 or cam_view.anchor_bottom != 1.0 or cam_view.offset_left != left or cam_view.offset_right != right or cam_view.offset_top != 0.0 or cam_view.offset_bottom != 0.0:
			cam_view.anchor_left = 0.5; cam_view.anchor_right = 0.5; cam_view.anchor_top = 0.0; cam_view.anchor_bottom = 1.0
			cam_view.offset_left = left; cam_view.offset_right = right; cam_view.offset_top = 0.0; cam_view.offset_bottom = 0.0
	else:
		if cam_view.anchor_left != 0.0 or cam_view.anchor_top != 0.0 or cam_view.anchor_right != 1.0 or cam_view.anchor_bottom != 1.0 or cam_view.offset_left != 0.0 or cam_view.offset_top != 0.0 or cam_view.offset_right != 0.0 or cam_view.offset_bottom != 0.0:
			cam_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _set_status(message: String) -> void:
	if message.begins_with("카메라 연결 끊김") or message.begins_with("카메라 프레임 지연") or message.begins_with("카메라 재시도") or message.begins_with("카메라 브리지 시작 실패"):
		camera_ready = false
		if state == BoothState.CALIBRATION and admin_panel != null:
			admin_panel.set_camera_status(0, 0, 0)
	status.text = message


func _start_sharing() -> void:
	var tunnel := OS.get_executable_path().get_base_dir().path_join("StreamingAssets/cloudflared.exe")
	if OS.has_feature("editor") or not FileAccess.file_exists(tunnel):
		tunnel = ProjectSettings.globalize_path("res://runtime/cloudflared.exe")
	photo_sharing.start(photos_dir, tunnel)

func _begin_capture():
	if photo_capture_flow.is_running() or state != BoothState.CAPTURE: return
	if photo_sharing != null and not photo_sharing.is_server_ready():
		_show_server_waiting_popup()
		photo_sharing.request_tunnel_restart()
		return
	if not camera_ready:
		status.text = "웹캠 연결을 확인해주세요"
		status.visible = true
		return
	var seconds := int(config.get("countdownSeconds", CAPTURE_SECONDS))
	if seconds < 3 or seconds > 15:
		seconds = CAPTURE_SECONDS
	var background_name := str(backgrounds[selected_index].get("bgName", "Unknown"))
	photo_capture_flow.start(seconds, background_name)

func _show_server_waiting_popup() -> void:
	if server_waiting_popup != null: server_waiting_popup.visible = true
	if server_waiting_timer != null: server_waiting_timer.start(SERVER_WAITING_POPUP_SECONDS)

func _dismiss_server_waiting_popup() -> void:
	if server_waiting_popup != null: server_waiting_popup.visible = false
	if server_waiting_timer != null: server_waiting_timer.stop()

func _retake(): _show_state(BoothState.CAPTURE)
func _home(): _show_state(BoothState.STANDBY)
func _do_result_action(): _retake() if result_index == 0 else _home()

func _idle_tick():
	if state not in [BoothState.STANDBY, BoothState.CALIBRATION]:
		idle_seconds += 1.0
		if idle_seconds >= IDLE_TIME_LIMIT: _home()

func _arm_picker() -> void:
	color_picker.activate()


func _on_color_picked(color: Color) -> void:
	config["global"]["targetColor"] = color.to_html(false)
	_apply_chroma()
	_save_config()

func _on_qr_ready(file_name: String, image: Image, succeeded: bool) -> void:
	photo_library.mark_qr_created(file_name, succeeded)
	if succeeded and file_name == last_photo_name:
		qr_view.texture = ImageTexture.create_from_image(image)
		status.text = "QR 생성 완료"
	elif not succeeded and file_name == last_photo_name:
		status.text = "사진 저장 완료 · 외부 QR을 만들지 못했습니다"

func _on_photo_saved(file_name: String) -> void:
	last_photo_name = file_name

func _notification(what: int):
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if camera_feed != null: camera_feed.stop()
		if photo_sharing != null: photo_sharing.stop()
