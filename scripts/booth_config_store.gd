extends RefCounted

const TEMPLATE_PATH := "res://data/config.json"

var _config_path := ""


func load_config() -> Dictionary:
	_resolve_config_path()
	if not FileAccess.file_exists(_config_path):
		_copy_template()
	var file := FileAccess.open(_config_path, FileAccess.READ)
	if file == null:
		return {"ok": false, "message": "config.json 열기 실패", "config": {"global": {}, "camera": {}, "backgrounds": []}}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary:
		return {"ok": false, "message": "config.json 형식 오류", "config": {}}
	return {"ok": true, "message": "", "config": parsed}


func save_config(config: Dictionary) -> bool:
	_resolve_config_path()
	var file := FileAccess.open(_config_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(config, "\t"))
	file.close()
	return true


func _resolve_config_path() -> void:
	if not _config_path.is_empty():
		return
	if OS.has_feature("editor"):
		_config_path = ProjectSettings.globalize_path(TEMPLATE_PATH)
		return
	var packaged_path := OS.get_executable_path().get_base_dir().path_join("StreamingAssets/config.json")
	_config_path = packaged_path if FileAccess.file_exists(packaged_path) else ProjectSettings.globalize_path(TEMPLATE_PATH)


func _copy_template() -> void:
	var template := FileAccess.open(TEMPLATE_PATH, FileAccess.READ)
	if template == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_config_path.get_base_dir()))
	var destination := FileAccess.open(_config_path, FileAccess.WRITE)
	if destination != null:
		destination.store_string(template.get_as_text())
		destination.close()
	template.close()
