extends Resource
class_name TVFContainer

# This is here because the .tvf format isn't a... y'know, Resource, but I wanted a way to store it as one.
# I also wasn't willing to mess with the ResourceFormatLoaders and Savers.
# I could actually use an EditorImportPlugin to store these in here...
# If you are reading this in the future and I did that, awesome.

var index: Dictionary = {}

@export_file("*tvf") var TVF_Path: String = "":
	set(v):
		TVF_Path = v

func _get_tvf_data(path: String):
	var t = TVF.new()
	if !FileAccess.file_exists(path):
		return
	t.load_from_file(path)
	
