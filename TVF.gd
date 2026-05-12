@tool
extends RefCounted
class_name TVF

const MAGIC := "TVF"
const VERSION := 2

var _text: bool
var _ttvf: TTVF
var file_path := ""
var index := {}

func _now():
	return Time.get_unix_time_from_system()

func _normalize_path(path:String, dir_mode:=false)->String:
	path = path.strip_edges().replace('\\','/')
	while path.begins_with('/'): path = path.substr(1)
	while path.find('//') != -1: path = path.replace('//','/')
	if dir_mode:
		if path != '' and not path.ends_with('/'): path += '/'
	else:
		if path.ends_with('/'): path = path.left(path.length()-1)
	return path

func make_dir(path:String):
	path = _normalize_path(path,true)
	if index.has(path): return
	index[path] = {"kind":"dir","created":_now(),"modified":_now()}

func add_file(path:String, type:String, disk_path:String):
	var f = FileAccess.open(disk_path, FileAccess.READ)
	if f == null:
		push_error('Failed to open: ' + disk_path)
		return
	var data = f.get_buffer(f.get_length())
	f.close()
	add_bytes(path, type, data)

func _ensure_parent_dirs(path:String):
	var parts = path.split('/')
	var cur = ''
	for i in range(parts.size()-1):
		cur += parts[i] + '/'
		make_dir(cur)

func add_bytes(path:String, type:String, data:PackedByteArray):
	path = _normalize_path(path,false)
	_ensure_parent_dirs(path)
	index[path] = {"kind":"file","type":type,"data":data,"offset":-1,"size":data.size(),"created":_now(),"modified":_now()}

func add_text(path:String, text:String): 
	add_bytes(path,'text',text.to_utf8_buffer())

func add_json(path:String, obj):
	add_bytes(path,'json',JSON.stringify(obj).to_utf8_buffer())

func save_to_file(path:String):
	file_path = path
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open for writing: " + path)
		return
	f.store_buffer(MAGIC.to_utf8_buffer())
	f.store_32(VERSION)
	var paths = index.keys(); paths.sort()
	f.store_32(paths.size())
	var pos = {}
	for p in paths:
		var e = index[p]
		_write_string(f,p)
		_write_string(f,e.get('kind','file'))
		_write_string(f,e.get('type',''))
		f.store_64(e.get('created',0))
		f.store_64(e.get('modified',0))
		pos[p] = f.get_position()
		f.store_64(0); f.store_64(0)
	for p in paths:
		var e = index[p]
		if e['kind'] == 'dir': continue
		var off = f.get_position()
		f.store_buffer(e['data'])
		var back = f.get_position()
		f.seek(pos[p]); f.store_64(off); f.store_64(e['data'].size()); f.seek(back)
	f.close()

func load_from_file(path:String):
	file_path = path
	index.clear()
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("Could not access ",path)
		return
	var header = f.get_buffer(MAGIC.length()).get_string_from_utf8()
	if header != MAGIC:
		f.close()
		printerr("File header, ", header, " not valid")
		return
	var ver = f.get_32()
	var count = f.get_32()
	for i in range(count):
		var p = _read_string(f)
		if ver >= 2:
			var kind = _read_string(f)
			var type = _read_string(f)
			var c = f.get_64()
			var m = f.get_64()
			var off = f.get_64()
			var sz = f.get_64()
			index[p] = {
				"kind": kind,
				"type": type,
				"created": c,
				"modified": m,
				"offset": off,
				"size": sz
			}
		else:
			
			var type1 = _read_string(f)
			var off1 = f.get_64()
			var sz1 = f.get_64()
			index[p] = {
				"kind": "file",
				"type": type1,
				"offset": off1,
				"size": sz1
			}
	f.close()

func read_bytes(path:String)->PackedByteArray:
	path = _normalize_path(path,false)
	if not index.has(path): 
		printerr("tvf file, ", path, " not found")
		return PackedByteArray()
	var e = index[path]
	if e['kind'] != 'file':
		return PackedByteArray()
	var f = FileAccess.open(file_path, FileAccess.READ)
	if f == null:
		push_error("Failed to open TVF: " + file_path)
		f.close()
		return PackedByteArray()
	if e['offset'] < 0 or e['size'] < 0:
		push_error("Invalid entry: " + path)
		f.close()
		return PackedByteArray()
	f.seek(e['offset'])
	var d = f.get_buffer(e['size'])
	f.close()
	return d

func get_text(path:String)->String: 
	return read_bytes(path).get_string_from_utf8()

func get_json(path:String):
	var txt = get_text(path)

	if txt.is_empty():
		push_error("Empty JSON file: " + path)
		return JSON.stringify({})

	var json = JSON.new()
	var err = json.parse(txt)

	if err != OK:
		push_error(
			"JSON parse error in: " + path +
			"\nLine: " + str(json.get_error_line()) +
			"\nMessage: " + json.get_error_message() +
			"\nContent:\n" + txt
		)
		return JSON.stringify({})

	return json.data

func exists(path:String)->bool:
	var fp = _normalize_path(path, false)
	var dir_path = _normalize_path(path, true)
	return index.has(fp) or index.has(dir_path)


func is_dir(path:String)->bool:
	path = _normalize_path(path,true)
	return index.has(path) and index[path]['kind']=='dir'


func is_file(path:String)->bool:
	path = _normalize_path(path,false)
	return index.has(path) and index[path]['kind']=='file'


func list_dir(path:String='')->Array[String]:
	path = _normalize_path(path,true)
	var out:Array[String]=[]
	for p in index.keys():
		if p.begins_with(path) and p != path:
			var rem = p.substr(path.length())
			var first = rem.split('/')[0]
			var child = path + first
			var dir_key = child if child.ends_with("/") else child + "/"
			if index.has(dir_key) and index[dir_key]["kind"] == "dir":
				child = dir_key
			if not out.has(child): out.append(child)
	return out


func _write_string(f,t): 
	var b=t.to_utf8_buffer()
	f.store_32(b.size()) 
	f.store_buffer(b)

func _read_string(f): 
	var s=f.get_32()
	return f.get_buffer(s).get_string_from_utf8()
