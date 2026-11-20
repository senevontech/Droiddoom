class_name AiLod
extends RefCounted
## AI level of detail (P1-08, TDD §3.4): how often an enemy thinks, based on
## its distance to the player. Rates come from the active QualityPreset, so
## low-end devices think less often. Movement still runs every physics frame;
## only decisions (state changes, line-of-sight rays, path requests) are slowed.

## Fallback when no preset is loaded (tests, editor).
const DEFAULT_INTERVAL: float = 0.05


## Seconds between two thinks for an enemy `distance` meters from the player.
static func interval_for(distance: float, preset: QualityPreset) -> float:
	if preset == null:
		return DEFAULT_INTERVAL
	var hz: float = preset.ai_tick_hz_far
	if distance < preset.ai_near_distance:
		hz = preset.ai_tick_hz_near
	elif distance < preset.ai_mid_distance:
		hz = preset.ai_tick_hz_mid
	return 1.0 / maxf(hz, 0.5)


## Random first delay inside one interval, so enemies spawned on the same
## frame don't all think on the same frames afterwards.
static func stagger(interval: float, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(0.0, interval)
