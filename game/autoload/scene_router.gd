extends Node
## Scene transitions, loading screens and (later) Zone sector streaming.
##
## Stub (P0-04). Async loading + transitions come in P2-01 / P2-10.


## Switches to the scene at `path`. Logs an error if the scene can't be loaded.
func go_to(path: String) -> void:
	var err: Error = get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("SceneRouter: failed to load %s (error %d)" % [path, err])


## Restarts the current scene from scratch (arena / mission retry).
func reload_current() -> void:
	var err: Error = get_tree().reload_current_scene()
	if err != OK:
		push_error("SceneRouter: failed to reload the current scene (error %d)" % err)
