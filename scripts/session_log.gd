extends Node
class_name SessionLogService
## 对局日志：每局写入 user://session_logs，网页同时记 localStorage，并可在游戏内下载。
## Autoload 名：SessionLog

const DIR_PLAY := "user://session_logs"
const DIR_GUT := "user://session_logs_gut"
const WEB_ERRORS := "rr.sessionLog.errors"
static var DIR := DIR_PLAY
const KEEP := 5
const WEB_CURRENT := "rr.sessionLog.current"
const WEB_PREVIOUS := "rr.sessionLog.previous"
const MAX_CHARS := 120000

static var session_id: String = ""
static var session_name: String = ""
static var file_path: String = ""
static var text: String = ""
static var _dirty: bool = false
static var _js_hooked: bool = false

func _ready() -> void:
	if under_gut():
		DIR = DIR_GUT
	restore_last()
	_hook_web_errors()
	set_process(true)


func _process(_delta: float) -> void:
	if _dirty:
		flush()


func _notification(what: int) -> void:
	if what in [NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_PREDELETE]:
		flush()


static func under_gut() -> bool:
	for a in OS.get_cmdline_args():
		if "gut_cmdln" in a or a == "-gexit" or a.begins_with("-gdir") or a.begins_with("-gtest"):
			return true
	return false


static func restore_last() -> void:
	if under_gut():
		DIR = DIR_GUT
		return
	var current := _read_web_key(WEB_CURRENT)
	if current.is_empty():
		var latest := _latest_file()
		if latest != "":
			var f := FileAccess.open(latest, FileAccess.READ)
			if f != null:
				current = f.get_as_text()
				file_path = latest
	if current.is_empty():
		return
	text = current
	_dirty = false


static func begin_session(kind: String, extra: Dictionary = {}) -> String:
	if under_gut():
		DIR = DIR_GUT
	flush()
	_archive_current_to_previous()
	var now := Time.get_datetime_dict_from_system()
	session_id = "%04d%02d%02d-%02d%02d%02d" % [int(now.year), int(now.month), int(now.day), int(now.hour), int(now.minute), int(now.second)]
	if session_id == _last_id:
		_seq += 1
		session_id = "%s-%d" % [session_id, _seq]
	else:
		_seq = 1
	_last_id = session_id
	session_name = kind
	text = ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	file_path = "%s/rr-%s-%s.log" % [DIR, session_id, _safe(kind)]
	var header := {
		"event": "session_start",
		"kind": kind,
		"version": GameVersion.STRING,
		"web": OS.has_feature("web"),
		"debug": OS.is_debug_build(),
		"locale": OS.get_locale(),
	}
	for k in extra:
		header[k] = extra[k]
	_append_raw("SESSION %s %s" % [session_id, JSON.stringify(header)])
	flush()
	_prune()
	return file_path

static var _last_id: String = ""
static var _seq: int = 1


static func info(msg: String) -> void:
	_append_raw(msg)


static func error(msg: String, extra: Dictionary = {}) -> void:
	var payload := {"event": "error", "message": msg}
	for k in extra:
		payload[k] = extra[k]
	_append_raw("ERROR " + JSON.stringify(payload), true)
	flush()


static func flame_event(kind: String, data: Dictionary = {}) -> void:
	var payload := data.duplicate()
	payload["event"] = "flame"
	payload["kind"] = kind
	_append_raw("FLAME " + JSON.stringify(payload), kind == "cap")
	if kind == "cap":
		flush()


static func flame_snapshot(stage: String, flames: Array, extra: Dictionary = {}) -> void:
	var by_type := {}
	var groups := 0
	var total := 0
	for f in flames:
		var key := str(f.get("effect_kind", f.get("id", "?")))
		var n := maxi(0, int(f.get("remaining", 0)))
		by_type[key] = int(by_type.get(key, 0)) + n
		groups += 1
		total += n
	var payload := extra.duplicate()
	payload["event"] = "flame"
	payload["kind"] = "snapshot"
	payload["stage"] = stage
	payload["total"] = total
	payload["groups"] = groups
	payload["by_type"] = by_type
	_append_raw("FLAME " + JSON.stringify(payload))


static func export_bundle() -> Dictionary:
	flush()
	var body := current_or_previous_text()
	var fname := "rr-session-%s.log" % (session_id if session_id != "" else "latest")
	return {
		"ok": not body.is_empty(),
		"text": body,
		"filename": fname,
		"path": file_path,
		"abs_path": ProjectSettings.globalize_path(file_path) if file_path != "" else "",
		"dir": ProjectSettings.globalize_path(DIR),
		"web": OS.has_feature("web"),
		"session_id": session_id,
	}


static func current_or_previous_text() -> String:
	var body := text
	if body.is_empty():
		body = _read_web_key(WEB_CURRENT)
	if body.is_empty():
		body = _read_web_key(WEB_PREVIOUS)
	if body.is_empty():
		var latest := _latest_file()
		if latest != "":
			var f := FileAccess.open(latest, FileAccess.READ)
			if f != null:
				body = f.get_as_text()
	var errs := _read_web_plain(WEB_ERRORS)
	if errs != "":
		body = (body + ("\n" if not body.ends_with("\n") and body != "" else "")) + errs
	return body


static func offer_download(host: Node = null) -> Dictionary:
	var bundle := export_bundle()
	if OS.has_feature("web"):
		_download_web(str(bundle.get("filename", "rr-session.log")), str(bundle.get("text", "")))
		bundle["delivered"] = "download"
	else:
		bundle["delivered"] = "file"
	if host != null and host.has_method("_on_session_log_exported"):
		host.call("_on_session_log_exported", bundle)
	return bundle


static func flush() -> void:
	if text.is_empty() and file_path == "":
		return
	_dirty = false
	if file_path != "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
		var f := FileAccess.open(file_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	_write_web_key(WEB_CURRENT, text)


static func _append_raw(msg: String, also_print: bool = false) -> void:
	var line := "[%s] %s" % [_now(), msg]
	text += line + "\n"
	if text.length() > MAX_CHARS:
		text = text.substr(text.length() - MAX_CHARS / 2)
	_dirty = true
	if also_print:
		print(line)


static func _now() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d" % [int(t.hour), int(t.minute), int(t.second)]


static func _safe(kind: String) -> String:
	var s := kind.strip_edges()
	if s.is_empty():
		return "play"
	return s.replace("/", "-").replace(" ", "-")


static func _archive_current_to_previous() -> void:
	if text.is_empty():
		return
	_write_web_key(WEB_PREVIOUS, text)
	flush()


static func _prune() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	var names: Array[String] = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".log"):
			names.append(n)
		n = d.get_next()
	names.sort()
	while names.size() > KEEP:
		d.remove(names[0])
		names.remove_at(0)


static func _latest_file() -> String:
	var d := DirAccess.open(DIR)
	if d == null:
		return ""
	var names: Array[String] = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.ends_with(".log"):
			names.append(n)
		n = d.get_next()
	if names.is_empty():
		return ""
	names.sort()
	return "%s/%s" % [DIR, names[names.size() - 1]]


static func _download_web(filename: String, body: String) -> void:
	if not OS.has_feature("web"):
		return
	var b64 := Marshalls.utf8_to_base64(body)
	var safe_name := filename.replace("'", "")
	JavaScriptBridge.eval(
		"(function(){try{var b64='%s';var bin=atob(b64);var arr=new Uint8Array(bin.length);for(var i=0;i<bin.length;i++)arr[i]=bin.charCodeAt(i);var blob=new Blob([arr],{type:'text/plain;charset=utf-8'});var a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='%s';document.body.appendChild(a);a.click();setTimeout(function(){URL.revokeObjectURL(a.href);a.remove();},500);}catch(e){console.error('[rr-log]',e);}})();" % [b64, safe_name],
		true
	)


static func _write_web_key(key: String, body: String) -> void:
	if not OS.has_feature("web"):
		return
	var b64 := Marshalls.utf8_to_base64(body)
	JavaScriptBridge.eval(
		"(function(){try{localStorage.setItem('%s','%s');}catch(e){console.error('[rr-log]',e);}})();" % [key, b64],
		true
	)


static func _read_web_plain(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var raw: Variant = JavaScriptBridge.eval(
		"(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})();" % key,
		true
	)
	return str(raw) if raw != null else ""


static func _read_web_key(key: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var raw: Variant = JavaScriptBridge.eval(
		"(function(){try{return localStorage.getItem('%s')||'';}catch(e){return '';}})();" % key,
		true
	)
	var stored := str(raw) if raw != null else ""
	if stored.is_empty():
		return ""
	var decoded := Marshalls.base64_to_utf8(stored)
	return decoded if decoded != "" else stored


func _hook_web_errors() -> void:
	if _js_hooked or not OS.has_feature("web"):
		return
	_js_hooked = true
	JavaScriptBridge.eval(
		"""
(function(){
  if (window.__rrLogHooked) return;
  window.__rrLogHooked = true;
  var rec=function(kind,msg,stack){
    try{
      var prev=localStorage.getItem('rr.sessionLog.current')||'';
      localStorage.setItem('rr.sessionLog.current', prev + '\\n['+new Date().toISOString()+'] ERROR {"event":"error","kind":"'+kind+'","message":'+JSON.stringify(String(msg||''))+',"stack":'+JSON.stringify(String(stack||''))+'}\\n');
    }catch(e){}
  };
  window.addEventListener('error', function(e){ rec('window', e.message, e.error && e.error.stack); });
  window.addEventListener('unhandledrejection', function(e){ rec('promise', e.reason, e.reason && e.reason.stack); });
})();
""",
		true
	)
