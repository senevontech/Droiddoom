@tool
extends EditorExportPlugin
## On Web exports, copies the scripts the HTML head include loads (export preset
## html/head_include) into the export folder, next to index.html.

const FILES: PackedStringArray = ["res://platform/web/senevon-account.js"]

var _dir: String = ""


func _get_name() -> String:
	return "DroidDoomWebFiles"


func _export_begin(features: PackedStringArray, _is_debug: bool, path: String, _flags: int) -> void:
	if not features.has("web"):
		_dir = ""
		return
	# Command-line export paths are relative to the project folder.
	var full: String = path
	if path.is_relative_path():
		full = ProjectSettings.globalize_path("res://").path_join(path).simplify_path()
	_dir = full.get_base_dir()


func _export_end() -> void:
	if _dir.is_empty():
		return
	for src: String in FILES:
		var dst: String = _dir.path_join(src.get_file())
		var err: Error = DirAccess.copy_absolute(ProjectSettings.globalize_path(src), dst)
		if err != OK:
			push_error("Web export: couldn't copy %s to %s (error %d)" % [src, dst, err])
	_dir = ""
