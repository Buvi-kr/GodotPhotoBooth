extends Node

signal status_changed(message: String)
signal qr_ready(file_name: String, image: Image, succeeded: bool)
signal page_visited(file_name: String)
signal photo_downloaded(file_name: String)

const FIRST_PORT := 8080
const LAST_PORT := 8089
const MAX_HEADER_BYTES := 16384
const BOOT_GRACE_MS := 10000
const RESTART_COOLDOWN_MS := 15000
const MAX_RESTARTS_PER_HOUR := 6

var photo_directory := ""
var _server := TCPServer.new()
var _port := 0
var _peers: Array[StreamPeerTCP] = []
var _request_buffers: Dictionary = {}
var _tunnel_pid := -1
var _tunnel_log := ""
var _cloudflared_path := ""
var _tunnel_started_ms := 0
var _last_restart_ms := 0
var _restart_pending := false
var _restart_times: Array[int] = []
var _public_url := ""
var _health_timer: Timer
var _health_request_active := false
var _next_log_poll_ms := 0


func _ready() -> void:
	_health_timer = Timer.new()
	_health_timer.wait_time = 10.0
	_health_timer.timeout.connect(_check_tunnel)
	add_child(_health_timer)
	_health_timer.start()


func start(output_directory: String, cloudflared_path: String) -> void:
	photo_directory = output_directory
	if not _start_http_server():
		status_changed.emit("사진 공유용 HTTP 서버를 열 수 없습니다")
		return
	if not FileAccess.file_exists(cloudflared_path):
		status_changed.emit("로컬 촬영 가능 · cloudflared가 없어 외부 QR은 꺼짐")
		return
	_cloudflared_path = cloudflared_path
	_tunnel_log = photo_directory.path_join("logs/tunnel_godot.log")
	DirAccess.make_dir_recursive_absolute(_tunnel_log.get_base_dir())
	_launch_tunnel()


func share_photo(file_name: String) -> void:
	if _public_url.is_empty():
		status_changed.emit("사진 저장됨 · 터널 연결 대기")
		qr_ready.emit(file_name, Image.new(), false)
		return
	var photo_url := _public_url + "/" + file_name.uri_encode()
	var qr_endpoint := "https://api.qrserver.com/v1/create-qr-code/?size=512x512&data=" + photo_url.uri_encode()
	var request := HTTPRequest.new()
	request.request_completed.connect(_on_qr_completed.bind(file_name, request))
	add_child(request)
	var error := request.request(qr_endpoint)
	if error != OK:
		request.queue_free()
		qr_ready.emit(file_name, Image.new(), false)
		status_changed.emit("QR 코드 요청을 시작하지 못했습니다")


func is_server_ready() -> bool:
	return not _public_url.is_empty()


func request_tunnel_restart() -> void:
	if _cloudflared_path.is_empty():
		return
	_restart_pending = true
	_attempt_tunnel_restart()


func stop() -> void:
	_server.stop()
	for peer in _peers:
		peer.disconnect_from_host()
	_peers.clear()
	_request_buffers.clear()
	if _tunnel_pid > 0:
		OS.kill(_tunnel_pid)
		_tunnel_pid = -1


func _process(_delta: float) -> void:
	if _tunnel_pid > 0 and not OS.is_process_running(_tunnel_pid):
		_tunnel_pid = -1
		_restart_pending = true
	_poll_tunnel()
	_service_http()


func _exit_tree() -> void:
	stop()


func _start_http_server() -> bool:
	for port in range(FIRST_PORT, LAST_PORT + 1):
		if _server.listen(port, "127.0.0.1") == OK:
			_port = port
			return true
	return false


func _poll_tunnel() -> void:
	if _tunnel_pid < 0 or not _public_url.is_empty() or Time.get_ticks_msec() < _next_log_poll_ms or not FileAccess.file_exists(_tunnel_log):
		return
	_next_log_poll_ms = Time.get_ticks_msec() + 500
	var log_file := FileAccess.open(_tunnel_log, FileAccess.READ)
	if log_file == null:
		return
	var log_length := log_file.get_length()
	log_file.seek(maxi(0, log_length - 8192))
	var log_text := log_file.get_as_text()
	log_file.close()
	var pattern := RegEx.new()
	pattern.compile("https://[a-zA-Z0-9-]+\\.trycloudflare\\.com")
	var match_result := pattern.search(log_text)
	if match_result != null and _public_url != match_result.get_string():
		_public_url = match_result.get_string()
		_restart_pending = false
		status_changed.emit("휴대전화 QR 공유 준비 완료")


func _check_tunnel() -> void:
	if _restart_pending:
		_attempt_tunnel_restart()
	if _public_url.is_empty() or _health_request_active:
		return
	var request := HTTPRequest.new()
	add_child(request)
	_health_request_active = true
	request.request_completed.connect(func(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
		_health_request_active = false
		if result != HTTPRequest.RESULT_SUCCESS or code != 200:
			_public_url = ""
			_restart_pending = true
			status_changed.emit("Cloudflare Tunnel 연결을 확인하는 중입니다")
		request.queue_free()
	)
	if request.request(_public_url + "/health") != OK:
		_health_request_active = false
		request.queue_free()
		_public_url = ""
		_restart_pending = true


func _launch_tunnel() -> void:
	_tunnel_started_ms = Time.get_ticks_msec()
	var log_file := FileAccess.open(_tunnel_log, FileAccess.WRITE)
	if log_file != null:
		log_file.close()
	_tunnel_pid = OS.create_process(_cloudflared_path, [
		"tunnel", "--url", "http://127.0.0.1:%d" % _port,
		"--http-host-header", "127.0.0.1", "--logfile", _tunnel_log,
	], false)
	if _tunnel_pid < 0:
		_restart_pending = true
		status_changed.emit("Cloudflare Tunnel 시작 실패")


func _attempt_tunnel_restart() -> void:
	if _cloudflared_path.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _tunnel_started_ms < BOOT_GRACE_MS:
		return
	while not _restart_times.is_empty() and now - _restart_times[0] >= 3600000:
		_restart_times.pop_front()
	if _restart_times.size() >= MAX_RESTARTS_PER_HOUR:
		_restart_pending = false
		status_changed.emit("터널 재시작 한도에 도달했습니다")
		return
	if _last_restart_ms > 0 and now - _last_restart_ms < RESTART_COOLDOWN_MS:
		return
	if _tunnel_pid > 0 and OS.is_process_running(_tunnel_pid):
		OS.kill(_tunnel_pid)
	_tunnel_pid = -1
	_public_url = ""
	_restart_pending = false
	_last_restart_ms = now
	_restart_times.append(now)
	_launch_tunnel()


func _service_http() -> void:
	if _server.is_connection_available():
		var peer := _server.take_connection()
		_peers.append(peer)
		_request_buffers[peer.get_instance_id()] = PackedByteArray()
	for peer: StreamPeerTCP in _peers.duplicate():
		peer.poll()
		if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_drop_peer(peer)
			continue
		var available: int = peer.get_available_bytes()
		if available <= 0:
			continue
		var packet: Array = peer.get_data(mini(available, MAX_HEADER_BYTES))
		if packet[0] != OK:
			_drop_peer(peer)
			continue
		var key: int = peer.get_instance_id()
		var request_data: PackedByteArray = _request_buffers.get(key, PackedByteArray())
		request_data.append_array(packet[1])
		if request_data.size() > MAX_HEADER_BYTES:
			_send_response(peer, 400, "Bad Request", "Request too large".to_utf8_buffer())
			_drop_peer(peer)
			continue
		_request_buffers[key] = request_data
		if request_data.get_string_from_utf8().contains("\r\n\r\n"):
			_handle_request(peer, request_data.get_string_from_utf8())
			_drop_peer(peer)


func _handle_request(peer: StreamPeerTCP, request_text: String) -> void:
	var lines := request_text.split("\r\n", false)
	var parts := lines[0].split(" ", false) if not lines.is_empty() else PackedStringArray()
	if parts.size() < 2 or parts[0] != "GET":
		_send_response(peer, 400, "Bad Request", "GET required".to_utf8_buffer())
		return
	var path := str(parts[1]).uri_decode()
	if path == "/health":
		_send_response(peer, 200, "OK", "OK".to_utf8_buffer())
		return
	if path.begins_with("/download_event/"):
		var file_name := path.trim_prefix("/download_event/")
		if not _is_photo_name(file_name) or not FileAccess.file_exists(photo_directory.path_join(file_name)):
			_send_response(peer, 404, "Not Found", "Not Found".to_utf8_buffer())
			return
		photo_downloaded.emit(file_name)
		_send_response(peer, 200, "OK", "OK".to_utf8_buffer())
		return
	if path.begins_with("/Photo_"):
		var file_name := path.trim_prefix("/")
		if not _is_photo_name(file_name) or not FileAccess.file_exists(photo_directory.path_join(file_name)):
			_send_response(peer, 404, "Not Found", "Not Found".to_utf8_buffer())
			return
		page_visited.emit(file_name)
		_send_response(peer, 200, "OK", _mobile_page(file_name).to_utf8_buffer(), "text/html; charset=utf-8")
		return
	if path.begins_with("/raw/") or path.begins_with("/download/"):
		var is_download := path.begins_with("/download/")
		var file_name := path.trim_prefix("/download/") if is_download else path.trim_prefix("/raw/")
		if not _is_photo_name(file_name):
			_send_response(peer, 400, "Bad Request", "Bad filename".to_utf8_buffer())
			return
		var file_path := photo_directory.path_join(file_name)
		if not FileAccess.file_exists(file_path):
			_send_response(peer, 404, "Not Found", "Not Found".to_utf8_buffer())
			return
		if is_download:
			photo_downloaded.emit(file_name)
		var extra_headers := PackedStringArray()
		if is_download:
			extra_headers.append("Content-Disposition: attachment; filename=\"%s\"" % "천문과학관_우주사진.jpg".uri_encode())
		_send_response(peer, 200, "OK", FileAccess.get_file_as_bytes(file_path), "image/jpeg", extra_headers)
		return
	_send_response(peer, 404, "Not Found", "Not Found".to_utf8_buffer())


func _send_response(peer: StreamPeerTCP, code: int, reason: String, body: PackedByteArray, content_type := "text/plain; charset=utf-8", extra_headers := PackedStringArray()) -> void:
	var header := "HTTP/1.1 %d %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n" % [code, reason, content_type, body.size()]
	for extra_header in extra_headers:
		header += extra_header + "\r\n"
	header += "\r\n"
	peer.put_data(header.to_utf8_buffer())
	peer.put_data(body)


func _drop_peer(peer: StreamPeerTCP) -> void:
	_request_buffers.erase(peer.get_instance_id())
	_peers.erase(peer)
	peer.disconnect_from_host()


func _is_photo_name(file_name: String) -> bool:
	return file_name.get_file() == file_name and file_name.begins_with("Photo_") and file_name.to_lower().ends_with(".jpg")


func _mobile_page(file_name: String) -> String:
	return "<!doctype html><html lang='ko'><meta charset='utf-8'><meta name='viewport' content='width=device-width,initial-scale=1'><title>천문과학관 포토부스</title><style>body{margin:0;padding:20px;background:#0b0c10;color:white;display:flex;flex-direction:column;align-items:center;font:18px Arial}.title{color:#66fcf1;font-size:1.3rem;font-weight:bold;line-height:1.4}img{max-width:100%%;height:auto;border:2px solid #45a29e;border-radius:15px;margin:20px 0 25px;box-shadow:0 8px 20px #0009}.download{display:inline-block;width:80%%;max-width:300px;padding:15px 30px;border-radius:30px;background:#45a29e;color:#0b0c10;text-align:center;text-decoration:none;font-size:1.2rem;font-weight:bold}.guide{margin-top:15px;color:#c5c6c7;text-align:center}</style><body><div class='title'>🌌 천문과학관 🌌<br>우주 탐험 기념사진 🚀</div><img src='/raw/%s' alt='우주 배경 합성 사진'><a class='download' href='/download/%s' download='천문과학관_우주사진.jpg' onclick=\"try{fetch('/download_event/%s')}catch(e){}\">📥 앨범에 사진 저장하기</a><div class='guide'>(아이폰 등 일부 기기는 사진을 길게 눌러 '저장'을 선택해주세요)</div></body></html>" % [file_name, file_name, file_name]


func _on_qr_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, file_name: String, request: HTTPRequest) -> void:
	var image := Image.new()
	var succeeded := result == HTTPRequest.RESULT_SUCCESS and code == 200 and image.load_png_from_buffer(body) == OK
	qr_ready.emit(file_name, image, succeeded)
	request.queue_free()
