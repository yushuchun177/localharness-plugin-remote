extends Node
## 远程操作插件 · local-harness
## 工具：remote_serve / remote_call / remote_ping / remote_stop
##
## 设计：
##   本机开一个极简 HTTP 端点（TCPServer + 手写 HTTP），
##   POST /task {"prompt":"..."} → 用本机的 llama-server 跑一轮 → 返回 {"reply":"..."}
##   另一台机器上的 Local-Harness 用 remote_call 就能把活派过来，
##   两台机器都不需要公网，局域网直连即可；模型永远在本机跑，数据不出局域网。
##
## 实现细节：模型调用用 curl 后台进程 + 轮询，避免卡住主线程。

const MAX_BODY := 65536
const JOB_TIMEOUT := 180.0

var _server: TCPServer = null
var _port: int = 0
var _jobs: Array = []          # 每个连接一条：{peer, buf, state, pid, out, req, t0, resp}
var _requests_served: int = 0


func _app() -> Node:
	var ml := Engine.get_main_loop()
	return ml.root.get_node_or_null("/root/App") if ml != null else null


func run(tool: String, args: Dictionary) -> Dictionary:
	match tool:
		"remote_serve":
			return _serve(args)
		"remote_call":
			return _call(args)
		"remote_ping":
			return _ping(args)
		"remote_stop":
			return _stop()
	return {"ok": false, "output": "未知工具：%s" % tool}


# ---------------------------------------------------------------- 服务端
func _serve(args: Dictionary) -> Dictionary:
	var port: int = clampi(int(args.get("port", 8799)), 1024, 65535)
	if _server != null:
		if _port == port:
			return {"ok": true, "output": "端点已经在 %d 上跑着了，累计处理 %d 个请求" % [_port, _requests_served]}
		_stop()
	_server = TCPServer.new()
	if _server.listen(port, "0.0.0.0") != OK:
		_server = null
		return {"ok": false, "output": "端口 %d 监听失败（被占用或没权限）" % port}
	_port = port
	set_process(true)
	return {"ok": true, "output": "已在 0.0.0.0:%d 开好端点。\nPOST /task {\"prompt\":\"...\"}\nGET /ping" % port}


func _stop() -> Dictionary:
	for j in _jobs:
		if j["peer"]:
			j["peer"].disconnect_from_host()
		if int(j["pid"]) > 0 and OS.is_process_running(int(j["pid"])):
			OS.kill(int(j["pid"]))
	_jobs.clear()
	if _server != null:
		_server.stop()
		_server = null
	set_process(false)
	var old := _port
	_port = 0
	return {"ok": true, "output": "端点已关闭（原端口 %d）" % old if old > 0 else "本来就没开"}


func _process(_dt: float) -> void:
	if _server == null:
		return
	# 1) 收新连接
	while _server.is_listening() and _server.is_connection_available():
		var peer := _server.take_connection()
		if peer == null:
			break
		_jobs.append({"peer": peer, "buf": "", "state": "read", "pid": -1,
			"out": "", "req": "", "t0": Time.get_ticks_msec(), "resp": ""})
	# 2) 读请求 / 等模型 / 回包
	for i in range(_jobs.size() - 1, -1, -1):
		var j: Dictionary = _jobs[i]
		var peer: StreamPeerTCP = j["peer"]
		if peer == null or peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			_jobs.remove_at(i)
			continue
		if j["state"] == "read":
			var avail := peer.get_available_bytes()
			if avail > 0:
				j["buf"] = str(j["buf"]) + peer.get_utf8_string(avail)
			if str(j["buf"]).length() > MAX_BODY:
				_respond(i, 413, {"error": "body too large"})
				continue
			var text: String = j["buf"]
			if text.find("\r\n\r\n") == -1:
				continue
			var head_end := text.find("\r\n\r\n")
			var head := text.substr(0, head_end)
			var body := text.substr(head_end + 4)
			var need := 0
			var re := RegEx.new()
			re.compile("(?i)content-length:\\s*(\\d+)")
			var m := re.search(head)
			if m:
				need = int(m.get_string(1))
			if body.length() < need and need > 0:
				# Content-Length 是字节数，中文一个字 3 字节，不能拿字符数比
				if body.to_utf8_buffer().size() < need:
					continue
			_handle_request(i, head, body.substr(0, need if need > 0 else body.length()))
		elif j["state"] == "wait":
			var pid: int = int(j["pid"])
			var expired := (Time.get_ticks_msec() - int(j["t0"])) / 1000.0 > JOB_TIMEOUT
			if pid > 0 and OS.is_process_running(pid) and not expired:
				continue
			var reply := _read_out(str(j["out"]))
			_respond(i, 200, {"reply": reply})
		# 超时的 read 连接直接丢掉
		elif (Time.get_ticks_msec() - int(j["t0"])) / 1000.0 > 30.0:
			_jobs.remove_at(i)


func _handle_request(idx: int, head: String, body: String) -> void:
	var j: Dictionary = _jobs[idx]
	var first := head.split("\r\n")[0] if head != "" else ""
	var parts := first.split(" ")
	if parts.size() < 2:
		_respond(idx, 400, {"error": "bad request"})
		return
	var method := parts[0].to_upper()
	var path := parts[1]

	if method == "GET" and path.begins_with("/ping"):
		_respond(idx, 200, {"ok": true, "app": "local-harness", "port": _port})
		return
	if not (method == "POST" and path.begins_with("/task")):
		_respond(idx, 404, {"error": "only POST /task and GET /ping"})
		return

	var obj = JSON.parse_string(body)
	var prompt := ""
	if obj is Dictionary:
		prompt = str(obj.get("prompt", "")).strip_edges()
	if prompt == "":
		_respond(idx, 400, {"error": "prompt is empty"})
		return

	var a := _app()
	if a == null or not bool(a.chat_ready()):
		_respond(idx, 503, {"error": "model not ready"})
		return

	# 起 curl 后台进程去问本地模型，等它写完文件
	var req := OS.get_temp_dir().path_join("lh_remote_req_%d.json" % randi())
	var out := OS.get_temp_dir().path_join("lh_remote_out_%d.json" % randi())
	var f := FileAccess.open(req, FileAccess.WRITE)
	if f == null:
		_respond(idx, 500, {"error": "temp file"})
		return
	f.store_string(JSON.stringify({
		"messages": [{"role": "user", "content": prompt}],
		"stream": false, "temperature": 0.5, "max_tokens": 512}))
	f.close()
	var pid := OS.create_process("curl.exe", PackedStringArray([
		"-s", "-m", str(int(JOB_TIMEOUT)), "-H", "Content-Type: application/json",
		"--data-binary", "@" + req, "-o", out,
		"http://127.0.0.1:%d/v1/chat/completions" % int(a.PORT)]), false)
	j["state"] = "wait"
	j["pid"] = pid
	j["out"] = out
	j["req"] = req
	j["t0"] = Time.get_ticks_msec()
	_requests_served += 1


func _read_out(path: String) -> String:
	var text := ""
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			text = f.get_as_text()
		DirAccess.remove_absolute(path)
	var obj = JSON.parse_string(text)
	if obj is Dictionary and obj.has("choices"):
		var ch: Array = obj["choices"]
		if ch.size() > 0 and ch[0] is Dictionary:
			var content = ch[0].get("message", {}).get("content", "")
			if typeof(content) == TYPE_STRING:
				return str(content).strip_edges()
	return ""


func _respond(idx: int, code: int, payload: Dictionary) -> void:
	var j: Dictionary = _jobs[idx]
	var peer: StreamPeerTCP = j["peer"]
	var body := JSON.stringify(payload)
	var reason: String = {200: "OK", 400: "Bad Request", 404: "Not Found",
		413: "Payload Too Large", 500: "Internal Error", 503: "Service Unavailable"}.get(code, "OK")
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json; charset=utf-8\r\n" % [code, reason]
	head += "Content-Length: %d\r\nConnection: close\r\n\r\n" % body.to_utf8_buffer().size()
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data(head.to_utf8_buffer())
		peer.put_data(body.to_utf8_buffer())
	if str(j["req"]) != "":
		DirAccess.remove_absolute(str(j["req"]))
	_jobs.remove_at(idx)


# ---------------------------------------------------------------- 客户端
func _call(args: Dictionary) -> Dictionary:
	var host := str(args.get("host", "")).strip_edges()
	var port: int = int(args.get("port", 8799))
	var prompt := str(args.get("prompt", "")).strip_edges()
	if host == "" or prompt == "":
		return {"ok": false, "output": "host 和 prompt 都要填"}
	var req := OS.get_temp_dir().path_join("lh_rcall_req_%d.json" % randi())
	var out := OS.get_temp_dir().path_join("lh_rcall_out_%d.json" % randi())
	var f := FileAccess.open(req, FileAccess.WRITE)
	if f == null:
		return {"ok": false, "output": "临时文件失败"}
	f.store_string(JSON.stringify({"prompt": prompt}))
	f.close()
	var res: Array = []
	var code := OS.execute("curl.exe", PackedStringArray([
		"-s", "-m", "200", "-H", "Content-Type: application/json",
		"--data-binary", "@" + req, "-o", out,
		"http://%s:%d/task" % [host, port]]), res, true)
	var text := ""
	if FileAccess.file_exists(out):
		var of := FileAccess.open(out, FileAccess.READ)
		if of:
			text = of.get_as_text()
		DirAccess.remove_absolute(out)
	DirAccess.remove_absolute(req)
	if str(text).strip_edges() == "":
		return {"ok": false, "output": "连不上 %s:%d（对方没开 remote_serve？）" % [host, port]}
	var obj = JSON.parse_string(text)
	if obj is Dictionary:
		if obj.has("reply"):
			return {"ok": true, "output": "[%s:%d] %s" % [host, port, str(obj["reply"])]}
		return {"ok": false, "output": "对方返回错误：" + str(obj.get("error", text.substr(0, 200)))}
	return {"ok": false, "output": "返回内容解析失败：" + str(text).substr(0, 200)}


func _ping(args: Dictionary) -> Dictionary:
	var host := str(args.get("host", "")).strip_edges()
	var port: int = int(args.get("port", 8799))
	if host == "":
		return {"ok": false, "output": "host 不能为空"}
	var out: Array = []
	var code := OS.execute("curl.exe", PackedStringArray([
		"-s", "-m", "8", "http://%s:%d/ping" % [host, port]]), out, true)
	if code != 0 or out.size() == 0 or str(out[0]).strip_edges() == "":
		return {"ok": true, "output": "× %s:%d 没响应" % [host, port]}
	var obj = JSON.parse_string(str(out[0]))
	if obj is Dictionary and bool(obj.get("ok", false)):
		return {"ok": true, "output": "✓ %s:%d 在线（Local-Harness）" % [host, port]}
	return {"ok": true, "output": "? %s:%d 有响应但不是 Local-Harness" % [host, port]}



