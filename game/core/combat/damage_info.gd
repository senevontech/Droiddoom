class_name DamageInfo
extends RefCounted
## One hit of damage (TDD §3.4). Created by the attacker, passed to a
## HurtboxComponent, which forwards it to a HealthComponent.

## Damage triangle (GDD §4.2). Order is saved in data: append only.
enum Type { KINETIC, ENERGY, EMP }

## Raw damage before hurtbox and resistance multipliers (crit already included).
var amount: float = 0.0
var type: Type = Type.KINETIC
## Who caused the hit (player, enemy, hazard). May be null.
var source: Node = null
## True if this hit was a critical (for VFX/SFX only; `amount` already includes it).
var crit: bool = false
## Push applied to the victim (world space, m/s).
var knockback: Vector3 = Vector3.ZERO
## Where the hit landed (world space). Used for impact VFX and damage numbers.
var hit_position: Vector3 = Vector3.ZERO
## Physical shove of the hit (world space, m/s). Wrecks fly along it when the
## hit kills (DebrisSystem); hit flinches lean along it.
var impulse: Vector3 = Vector3.ZERO


## Convenience constructor.
static func create(
	p_amount: float, p_type: Type, p_source: Node = null, p_hit_position: Vector3 = Vector3.ZERO
) -> DamageInfo:
	var info: DamageInfo = DamageInfo.new()
	info.amount = p_amount
	info.type = p_type
	info.source = p_source
	info.hit_position = p_hit_position
	return info


## Final damage after the hurtbox zone multiplier and the victim's
## resistances. Never negative. Pure function: unit-tested.
static func resolve(
	p_amount: float, p_type: Type, zone_multiplier: float, resistances: DamageResistances
) -> float:
	var resist: float = resistances.multiplier(p_type) if resistances != null else 1.0
	return maxf(0.0, p_amount * zone_multiplier * resist)
