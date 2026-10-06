extends Node

const CSV_HEADER := "datetime,bg_name,qr_ok,page_visited,downloaded,error_type"
const PHOTO_PREFIX := "Photo_"
const CLEANUP_AFTER_DAYS := 1
const MIN_KEEP_COUNT := 0
const CLEANUP_BATCH_SIZE := 20

var directory := ""
var _log_rows: Dictionary = {}


func configure(photo_directory: String) -> void:
	directory = photo_directory
	DirAccess.make_dir_recursive_absolute(directory)
	call_deferred("_cleanup_old_photos")


func save_photo(image: Image, background_name: String) -> String:
	if image == null or image.is_empty():
		return ""
	var file_name := PHOTO_PREFIX + Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_").trim_suffix("Z") + ".jpg"
	var destination := directory.path_join(file_name)
	var suffix := 1
	while FileAccess.file_exists(destination):
		file_name = PHOTO_PREFIX + Time.get_datetime_string_from_system().replace("-", "").replace(":", "").replace("T", "_").trim_suffix("Z") + "_%d.jpg" % suffix
		destination = directory.path_join(file_name)
		suffix += 1
	if image.save_jpg(destination, 0.95) != OK:
		return ""
	_record_capture(file_name, background_name)
	return file_name


func mark_qr_created(file_name: String, succeeded: bool) -> void:
	_update_stat(file_name, 2, succeeded)


func mark_page_visited(file_name: String) -> void:
	_update_stat(file_name, 3, true)


func mark_downloaded(file_name: String) -> void:
	_update_stat(file_name, 4, true)


func _record_capture(file_name: String, background_name: String) -> void:
	var logs_dir := directory.path_join("logs")
	DirAccess.make_dir_recursive_absolute(logs_dir)
	var month := Time.get_datetime_string_from_system().substr(0, 7).replace("-", "")
	var path := logs_dir.path_join("capture_history_%s.csv" % month)
	var existed := FileAccess.file_exists(path)
	var file := FileAccess.open(path, FileAccess.READ_WRITE if existed else FileAccess.WRITE)
	if file == null:
		return
	var rows: PackedStringArray
	if existed:
		rows = file.get_as_text().split("\n", false)
	else:
		rows = PackedStringArray()
	file.seek_end()
	if rows.is_empty():
		file.store_line(CSV_HEADER)
		rows.append(CSV_HEADER)
	var row_index: int = rows.size()
	var timestamp := Time.get_datetime_string_from_system().replace("T", " ").trim_suffix("Z")
	var safe_background := background_name.replace(",", "_").replace("\n", " ")
	file.store_line("%s,%s,0,0,0,NONE" % [timestamp, safe_background])
	file.close()
	_log_rows[file_name] = {"path": path, "row": row_index}


func _update_stat(file_name: String, column: int, succeeded: bool) -> void:
	if not _log_rows.has(file_name):
		return
	var record: Dictionary = _log_rows[file_name]
	var path: String = record.path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var rows := file.get_as_text().split("\n", false)
	file.close()
	var row_index := int(record.row)
	if row_index >= rows.size():
		return
	var fields := rows[row_index].split(",")
	if column >= fields.size() or (fields[column] == "1" and succeeded):
		return
	fields[column] = "1" if succeeded else "0"
	if column == 2 and not succeeded and fields.size() > 5 and fields[5] == "NONE":
		fields[5] = "QR_FAIL"
	rows[row_index] = ",".join(fields)
	file = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(rows) + "\n")
		file.close()


func _cleanup_old_photos() -> void:
	# Match Unity's startup coroutine: let kiosk initialization settle before disk work.
	await get_tree().process_frame
	await get_tree().process_frame
	var folder := DirAccess.open(directory)
	if folder == null:
		return
	var names: Array[String] = []
	for file_name in folder.get_files():
		if file_name.begins_with(PHOTO_PREFIX) and file_name.to_lower().ends_with(".jpg"):
			names.append(file_name)
	if names.size() <= MIN_KEEP_COUNT:
		return
	if MIN_KEEP_COUNT > 0:
		names.sort_custom(func(a: String, b: String) -> bool:
			return FileAccess.get_modified_time(directory.path_join(a)) > FileAccess.get_modified_time(directory.path_join(b))
		)
	var cutoff := int(Time.get_unix_time_from_system()) - CLEANUP_AFTER_DAYS * 86400
	var processed := 0
	for index in range(MIN_KEEP_COUNT, names.size()):
		var file_name: String = names[index]
		var path := directory.path_join(file_name)
		if FileAccess.get_modified_time(path) < cutoff:
			DirAccess.remove_absolute(path)
		processed += 1
		if processed % CLEANUP_BATCH_SIZE == 0:
			await get_tree().process_frame
