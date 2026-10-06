extends Node

signal frame_received(image: Image)
signal status_changed(message: String)

const PORT := 49152
const FRAME_HEADER_BYTES := 16
const MAX_FRAME_BYTES := 32 * 1024 * 1024
const NO_FRAME_TIMEOUT_MS := 12000
const HELPER_RETRY_DELAY_MS := 5000
const MAX_HELPER_RESTARTS_PER_HOUR := 6

var _peer := StreamPeerTCP.new()
var _buffer := PackedByteArray()
var _buffer_offset := 0
var _expected_size := -1
var _frame_width := 0
var _frame_height := 0
var _frame_format := 0
var _process_id := -1
var _next_connect_ms := 0
var _last_frame_ms := 0
var _helper_restart_times: Array[int] = []
var _camera_config: Dictionary = {}
var _helper_path := ""
var _stopped := false


func start(camera_config: Dictionary, helper_path: String) -> void:
	_camera_config = camera_config
	_helper_path = helper_path
	_stopped = false
	_reset_peer()
	_process_id = -1
	_last_frame_ms = Time.get_ticks_msec()
	if OS.get_name() != "Windows":
		status_changed.emit("Windows 전용 카메라 브리지")
		return
	if not FileAccess.file_exists(helper_path):
		status_changed.emit("CameraBridge 없음 · 빌드 스크립트를 실행하세요")
		return

	_launch_helper()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	if _process_id > 0 and not OS.is_process_running(_process_id):
		_process_id = -1
		_reset_peer()
		if _schedule_helper_restart(now):
			status_changed.emit("카메라 연결 끊김 · 재연결을 시도합니다")
		return
	if _process_id > 0 and now - _last_frame_ms >= NO_FRAME_TIMEOUT_MS:
		OS.kill(_process_id)
		_process_id = -1
		_reset_peer()
		if _schedule_helper_restart(now):
			status_changed.emit("카메라 프레임 지연 · 브리지를 재시작합니다")
		return
	if _process_id < 0 and not _stopped and now >= _next_connect_ms:
		_launch_helper()
	_peer.poll()
	var peer_status := _peer.get_status()
	if peer_status in [StreamPeerTCP.STATUS_NONE, StreamPeerTCP.STATUS_ERROR]:
		# A refused initial connection and a later disconnect can leave the peer in
		# STATUS_ERROR. Reset it before retrying, and discard any partial old frame.
		_buffer.clear()
		_buffer_offset = 0
		_expected_size = -1
		_frame_width = 0
		_frame_height = 0
		_frame_format = 0
		if peer_status == StreamPeerTCP.STATUS_ERROR:
			_peer.disconnect_from_host()
			peer_status = _peer.get_status()
		if peer_status == StreamPeerTCP.STATUS_NONE and now >= _next_connect_ms:
			_connect()
		return
	if peer_status != StreamPeerTCP.STATUS_CONNECTED:
		return

	var available := _peer.get_available_bytes()
	if available > 0:
		var packet := _peer.get_data(available)
		if packet[0] == OK:
			_buffer.append_array(packet[1])
	_consume_frames()


func stop() -> void:
	_stopped = true
	_peer.disconnect_from_host()
	if _process_id > 0:
		OS.kill(_process_id)
		_process_id = -1


func _connect() -> void:
	_next_connect_ms = Time.get_ticks_msec() + 2000
	_peer.connect_to_host("127.0.0.1", PORT)


func _launch_helper() -> void:
	if _helper_path.is_empty() or not FileAccess.file_exists(_helper_path):
		_next_connect_ms = Time.get_ticks_msec() + HELPER_RETRY_DELAY_MS
		return
	var arguments: Array[String] = [
		"--width", str(_camera_config.get("requestedWidth", 1920)),
		"--height", str(_camera_config.get("requestedHeight", 1080)),
		"--fps", str(_camera_config.get("requestedFPS", 30)),
		"--port", str(PORT),
	]
	if not bool(_camera_config.get("useDefaultDevice", true)) and not str(_camera_config.get("deviceName", "")).is_empty():
		arguments.append_array(["--device", str(_camera_config.get("deviceName", ""))])
	_process_id = OS.create_process(_helper_path, arguments, false)
	_last_frame_ms = Time.get_ticks_msec()
	if _process_id < 0:
		if _schedule_helper_restart(_last_frame_ms):
			status_changed.emit("카메라 브리지 시작 실패 · 재시도 대기")
	else:
		_next_connect_ms = Time.get_ticks_msec() + 2000
		_connect()


func _reset_peer() -> void:
	_peer.disconnect_from_host()
	_buffer.clear()
	_buffer_offset = 0
	_expected_size = -1
	_frame_width = 0
	_frame_height = 0
	_frame_format = 0


func _schedule_helper_restart(now: int) -> bool:
	while not _helper_restart_times.is_empty() and now - _helper_restart_times[0] >= 3600000:
		_helper_restart_times.pop_front()
	if _helper_restart_times.size() >= MAX_HELPER_RESTARTS_PER_HOUR:
		_next_connect_ms = _helper_restart_times[0] + 3600000
		status_changed.emit("카메라 재시도 한도 도달 · 잠시 후 다시 시도합니다")
		return false
	_helper_restart_times.append(now)
	_next_connect_ms = now + HELPER_RETRY_DELAY_MS
	return true


func _consume_frames() -> void:
	var newest_payload_offset := -1
	var newest_size := 0
	var newest_width := 0
	var newest_height := 0
	var newest_format := 0
	while true:
		if _expected_size < 0:
			if _buffer.size() - _buffer_offset < FRAME_HEADER_BYTES:
				break
			_expected_size = _read_uint32_be(_buffer, _buffer_offset)
			_frame_width = _read_uint32_be(_buffer, _buffer_offset + 4)
			_frame_height = _read_uint32_be(_buffer, _buffer_offset + 8)
			_frame_format = _read_uint32_be(_buffer, _buffer_offset + 12)
			_buffer_offset += FRAME_HEADER_BYTES
			var expected_raw_size := _frame_width * _frame_height * 3
			var valid_size := (_frame_format == 0 and _expected_size == expected_raw_size) or (_frame_format == 1 and _expected_size >= 4)
			if _frame_width < 16 or _frame_height < 16 or _frame_width > 8192 or _frame_height > 8192 or not valid_size or _expected_size > MAX_FRAME_BYTES:
				if newest_payload_offset >= 0:
					_emit_frame(newest_payload_offset, newest_size, newest_width, newest_height, newest_format)
					newest_payload_offset = -1
				_buffer.clear()
				_buffer_offset = 0
				_expected_size = -1
				status_changed.emit("카메라 프레임 크기가 올바르지 않습니다")
				break
		if _buffer.size() - _buffer_offset < _expected_size:
			break
		newest_payload_offset = _buffer_offset
		newest_size = _expected_size
		newest_width = _frame_width
		newest_height = _frame_height
		newest_format = _frame_format
		_buffer_offset += _expected_size
		_last_frame_ms = Time.get_ticks_msec()
		_expected_size = -1
		_frame_width = 0
		_frame_height = 0
		_frame_format = 0

	if newest_payload_offset >= 0:
		_emit_frame(newest_payload_offset, newest_size, newest_width, newest_height, newest_format)

	# Keep incomplete headers/frames in place and compact only after consuming data.
	# This avoids copying a large frame merely to remove its header.
	if _buffer_offset >= _buffer.size():
		_buffer.clear()
		_buffer_offset = 0
	elif _buffer_offset >= 65536:
		_buffer = _buffer.slice(_buffer_offset)
		_buffer_offset = 0


func _emit_frame(payload_offset: int, payload_size: int, width: int, height: int, format: int) -> void:
	var encoded_frame := _buffer.slice(payload_offset, payload_offset + payload_size)
	if format == 1:
		var image := Image.new()
		if image.load_jpg_from_buffer(encoded_frame) != OK or image.get_width() != width or image.get_height() != height:
			status_changed.emit("카메라 JPEG 프레임을 읽을 수 없습니다")
			return
		frame_received.emit(image)
	else:
		frame_received.emit(Image.create_from_data(width, height, false, Image.FORMAT_RGB8, encoded_frame))


func _read_uint32_be(data: PackedByteArray, offset: int) -> int:
	return (int(data[offset]) << 24) | (int(data[offset + 1]) << 16) | (int(data[offset + 2]) << 8) | int(data[offset + 3])


func _exit_tree() -> void:
	stop()
