extends RefCounted


func apply(material: ShaderMaterial, config: Dictionary, backgrounds: Array, frame: Image, index: int = -1, neutral_grading: bool = false) -> void:
	if material == null or config.is_empty():
		return
	var active_index := clampi(index, 0, max(0, backgrounds.size() - 1))
	var global_settings: Dictionary = config.get("global", {})
	var background: Dictionary = backgrounds[active_index] if not backgrounds.is_empty() else {}
	var color_settings: Dictionary = background.get("color", {})
	material.set_shader_parameter("target_color", Color.from_string(str(global_settings.get("targetColor", "#00B140")), Color.GREEN))
	for pair in [["sensitivity", "masterSensitivity"], ["smoothness", "masterSmoothness"], ["spill_removal", "masterSpillRemoval"], ["luma_weight", "masterLumaWeight"], ["edge_choke", "masterEdgeChoke"]]:
		material.set_shader_parameter(pair[0], float(global_settings.get(pair[1], 0.0)) * 0.01)
	material.set_shader_parameter("pre_blur", float(global_settings.get("masterPreBlur", 0.0)) * 0.05)
	material.set_shader_parameter("brightness", 0.0 if neutral_grading else _scale_value(float(color_settings.get("brightness", 0)), 100.0, 0.0))
	material.set_shader_parameter("contrast", 1.0 if neutral_grading else _scale_value(float(color_settings.get("contrast", 100)), 100.0, 1.0))
	material.set_shader_parameter("saturation", 1.0 if neutral_grading else _scale_value(float(color_settings.get("saturation", 100)), 100.0, 1.0))
	material.set_shader_parameter("hue_degrees", 0.0 if neutral_grading else float(color_settings.get("hue", 0)))
	var crop: Dictionary = global_settings.get("masterCrop", {})
	var camera: Dictionary = config.get("camera", {})
	var width := float(camera.get("requestedWidth", 1920))
	var height := float(camera.get("requestedHeight", 1080))
	# Godot texture UV starts at the top-left; Unity crop data stores physical top/bottom edges.
	material.set_shader_parameter("crop_rect", Vector4(float(crop.get("left", 0)) / width, float(crop.get("top", 0)) / height, 1.0 - float(crop.get("right", 0)) / width, 1.0 - float(crop.get("bottom", 0)) / height))
	material.set_shader_parameter("crop_fade", Vector2(float(crop.get("fadeX", 0)) / width, float(crop.get("fadeY", 0)) / height))
	var frame_width := float(frame.get_width()) if frame != null else width
	var frame_height := float(frame.get_height()) if frame != null else height
	material.set_shader_parameter("capture_aspect", frame_width / maxf(frame_height, 1.0))


func _scale_value(value: float, divisor: float, fallback: float) -> float:
	if value == 0.0:
		return fallback
	if fallback != 0.0 and absf(value) <= 2.0:
		return value
	return value / divisor
