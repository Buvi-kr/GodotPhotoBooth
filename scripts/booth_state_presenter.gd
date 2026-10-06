extends RefCounted

const State = preload("res://scripts/booth_state.gd").Value


func apply(state: int, controls: Dictionary, local_admin: bool) -> void:
	var is_standby := state == State.STANDBY
	var is_selecting := state == State.SELECT_BG
	var is_live_capture := state in [State.CAPTURE, State.PROCESSING]
	var is_calibrating := state == State.CALIBRATION
	var is_result := state == State.RESULT

	controls.bg_view.visible = is_live_capture or local_admin
	controls.cam_view.visible = state in [State.CAPTURE, State.CALIBRATION, State.PROCESSING]
	controls.front_view.visible = is_live_capture or local_admin
	controls.cam_view.material = null if is_standby else controls.chroma_material
	controls.ui_layer.visible = true
	controls.prompt.visible = is_standby or is_selecting
	controls.prompt.text = "아무 키나 눌러주세요" if is_standby else "배경을 선택해주세요"
	controls.prompt.add_theme_font_size_override("font_size", 100 if is_standby else 90)
	if is_selecting:
		controls.prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
		controls.prompt.offset_left = -600
		controls.prompt.offset_right = 600
		controls.prompt.offset_top = -255
		controls.prompt.offset_bottom = -105
		# Unity layers the selection video over clickable cells, so keep the transparent buttons beneath it.
		controls.select_video.move_to_front()
		controls.navigation_cursor.move_to_front()
		controls.prompt.move_to_front()
	else:
		controls.prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		controls.prompt.offset_left = -500
		controls.prompt.offset_right = 500
		controls.prompt.offset_top = 250
		controls.prompt.offset_bottom = 450

	controls.timer_label.visible = is_live_capture
	controls.bg_buttons.visible = is_selecting
	controls.bg_buttons.modulate.a = 0.0 if is_selecting else 1.0
	controls.result_panel.visible = is_result
	controls.capture_button.visible = state == State.CAPTURE
	controls.status.visible = is_calibrating
	controls.admin_panel.visible = is_calibrating
	controls.standby_video.visible = is_standby
	controls.select_video.visible = is_selecting
	controls.navigation_cursor.visible = false

	if is_standby:
		controls.select_video.stop()
		controls.standby_video.stream = load("res://assets/videos/standby.ogv") as VideoStream
		controls.standby_video.loop = true
		controls.standby_video.play()
	elif is_selecting:
		controls.standby_video.stop()
		controls.select_video.loop = true
		controls.select_video.play()
	else:
		controls.standby_video.stop()
		controls.select_video.stop()
