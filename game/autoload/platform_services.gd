extends Node
## Facade over platform SDKs: ads, store/IAP, achievements, leaderboards,
## cloud save and analytics (TDD §3.3).
##
## ONLY code under res://platform/ may call SDKs (AGENTS.md rule 4).
## Stub (P0-04). Providers come in Phase 4/5.


## True if the game was launched with flag `name`: `-- --<name>` on the
## command line (desktop), or `?<name>` in the page URL (web).
func has_launch_flag(name: String) -> bool:
	if OS.get_cmdline_user_args().has("--" + name):
		return true
	return WebLaunch.has_query_flag(name)


## Returns a short id for the current platform: steam, web, android, ios, desktop.
func get_platform_id() -> StringName:
	if OS.has_feature("steam"):
		return &"steam"
	if OS.has_feature("web"):
		return &"web"
	if OS.has_feature("android"):
		return &"android"
	if OS.has_feature("ios"):
		return &"ios"
	return &"desktop"
