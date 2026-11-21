extends Node
## Global signal hub. It holds no state.
##
## Systems emit and listen here instead of referencing each other directly
## (TDD §3.1). Add new signals here, in past tense, with typed arguments.

@warning_ignore_start("unused_signal")

# --- Combat ---
signal enemy_died(enemy: Node, killer: Node)
## A droid took damage (after multipliers). `source` = who dealt it (may be
## null). The HUD shows hit markers for the player's hits.
signal enemy_hit(enemy: Node, amount: float, crit: bool, source: Node)
signal player_damaged(amount: float, damage_type: int)
signal player_died
## HOLLOW picked up a droid drop (`kind` = &"repair" / &"ammo", `amount` =
## hull restored or rounds added).
signal pickup_collected(kind: StringName, amount: int, position: Vector3)
## HOLLOW started a dash (horizontal unit direction).
signal player_dashed(direction: Vector3)
## A dash dodged `threats` hits that were about to land (GDD §4.4). The
## slow-motion + damage bonus reward listens here (P1-13).
signal neural_sync_triggered(threats: int)
## The Neural Sync slow-motion reward ended (time is back to normal).
signal neural_sync_ended
## A weapon started reloading (or cooling down). `weapon` is a Weapon node.
signal weapon_reload_started(weapon: Node3D)
## A weapon fired (any mode). `weapon` is a Weapon node: FX read its data
## (flash size, type), enemies hear it (noise_radius, P1-17).
signal weapon_fired(weapon: Node3D, muzzle: Vector3, direction: Vector3)
## A beam weapon drew its beam this tick (from muzzle to where it stopped).
signal beam_drawn(from: Vector3, to: Vector3, width: float, damage_type: int)
## Something exploded (rockets, grenades, later Kamikazes and barrels).
signal explosion_happened(position: Vector3, radius: float, damage_type: int)
## `source` should trail smoke for `duration` s (-1 = until it is freed).
## Badly damaged droids and burning wrecks use it; CombatFX draws it.
signal smoke_source_added(source: Node3D, duration: float)
## A shot or blast hit something. `on_target` = it hit a hurtbox, not a wall.
signal hit_landed(position: Vector3, normal: Vector3, damage_type: int, on_target: bool)

# --- Mission flow ---
signal mission_started(mission_id: StringName)
signal mission_completed(mission_id: StringName, stars: int)
signal mission_failed(mission_id: StringName)
signal wave_started(index: int)
## Every droid of the wave is dead (the break before the next wave starts).
signal wave_cleared(index: int)

# --- Economy / progression ---
signal scrap_collected(amount: int)
signal currency_changed(currency: StringName, new_amount: int)

# --- Settings / system ---
signal camera_mode_changed(mode: int)
## A player setting changed (Settings.set_value). `key` = the setting's name.
signal settings_changed(key: StringName)
signal quality_preset_changed(preset: int)
signal input_device_changed(device: int)

@warning_ignore_restore("unused_signal")
