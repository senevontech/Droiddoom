class_name WebLaunch
extends RefCounted
## Reads launch flags from the page URL on the Web (`index.html?benchmark`).
## Only code in res://platform/ may touch JavaScriptBridge (AGENTS.md rule 4).


## True if the page URL's query string has `name` (e.g. `?benchmark`).
static func has_query_flag(name: String) -> bool:
	if not OS.has_feature("web"):
		return false
	var safe: String = name.validate_filename().replace("'", "")
	var script: String = "new URLSearchParams(window.location.search).has('%s')" % safe
	return bool(JavaScriptBridge.eval(script, true))
