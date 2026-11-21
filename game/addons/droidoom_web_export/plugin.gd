@tool
extends EditorPlugin
## Registers WebFilesExport (copies the page scripts on Web exports, D-035).

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/droidoom_web_export/web_files_export.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
