@tool
extends RefCounted
class_name TTVF

const MAGIC := "TTVF"
const VERSION := 2

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

func save_to_text_file(path:String):
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Failed to open file for writing")
		return
	
	f.store_line(MAGIC + " " + str(VERSION))
	f.store_line("")
	
	var paths = index.keys()
	paths.sort()
	
	for p in paths:
		var e = index[p]
		
		if e["kind"] == "dir":
			f.store_line("dir " + p)
			continue
		
		# FILE
		f.store_line("file " + p)
		f.store_line("type " + e.get("type", ""))
		f.store_line("created " + str(e.get("created", 0)))
		f.store_line("modified " + str(e.get("modified", 0)))
		
		var data:PackedByteArray = e.get("data", PackedByteArray())
		
		var is_text = e.get("type","") in ["text", "json"]
		
		if not is_text:
			f.store_line("encoding base64")
			data = Marshalls.raw_to_base64(data).to_utf8_buffer()
		
		f.store_line("data <<EOF")
		f.store_string(data.get_string_from_utf8())
		f.store_line("")
		f.store_line("EOF")
		f.store_line("")
	
	f.close()

func load_from_text_file(path:String):
	file_path = path
	index.clear()
	
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	
	var header = f.get_line()
	if not header.begins_with(MAGIC):
		push_error("Invalid TTVF file")
		return
	
	var current_path = ""
	var current = {}
	var reading_data = false
	var data_lines:Array[String] = []
	
	while not f.eof_reached():
		var line = f.get_line()
		
		if reading_data:
			if line == "EOF":
				var text = "\n".join(data_lines)
				
				if current.get("encoding","") == "base64":
					current["data"] = Marshalls.base64_to_raw(text)
				else:
					current["data"] = text.to_utf8_buffer()
				
				index[current_path] = current
				
				reading_data = false
				data_lines.clear()
				continue
			else:
				data_lines.append(line)
				continue
		
		if line.strip_edges() == "":
			continue
		
		if line.begins_with("dir "):
			var p = _normalize_path(line.substr(4), true)
			index[p] = {
				"kind":"dir",
				"created":_now(),
				"modified":_now()
			}
		
		elif line.begins_with("file "):
			current_path = _normalize_path(line.substr(5), false)
			current = {
				"kind":"file",
				"type":"",
				"created":0,
				"modified":0
			}
		
		elif line.begins_with("type "):
			current["type"] = line.substr(5)
		
		elif line.begins_with("created "):
			current["created"] = int(line.substr(8))
		
		elif line.begins_with("modified "):
			current["modified"] = int(line.substr(9))
		
		elif line.begins_with("encoding "):
			current["encoding"] = line.substr(9)
		
		elif line.begins_with("data <<"):
			reading_data = true
			data_lines.clear()
	
	f.close()

func read_bytes(path:String) -> PackedByteArray:
	path = _normalize_path(path, false)
	
	if not index.has(path):
		return PackedByteArray()
	
	var e = index[path]
	
	if e["kind"] != "file":
		return PackedByteArray()
	
	return e.get("data", PackedByteArray())

func get_text(path:String)->String: 
	return read_bytes(path).get_string_from_utf8()

func get_json(path:String): 
	return JSON.parse_string(get_text(path))

func exists(path:String)->bool: 
	return index.has(_normalize_path(path)) or index.has(_normalize_path(path,true))

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
			if index.has(child + '/'): child += '/'
			if not out.has(child): out.append(child)
	return out

func _write_string(f,t): 
	var b=t.to_utf8_buffer()
	f.store_32(b.size()) 
	f.store_buffer(b)

func _read_string(f): 
	var s=f.get_32()
	return f.get_buffer(s).get_string_from_utf8()
