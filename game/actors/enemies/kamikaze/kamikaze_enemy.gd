class_name KamikazeEnemy
extends BaseEnemy
## Suicide droid (P1-09, GDD §6). Rolls at the target; in range it arms
## (core flashes + a red ring on the ground shows the blast radius, so it
## reads in both cameras), then destroys itself. Its death blast comes from
## `data.death_blast_*` (BaseEnemy), so shooting it early also sets it off,
## hurting any droids packed around it.
##
## Scene contract (on top of BaseEnemy's): `WarningRing` (MeshInstance3D,
## radius 1 m, outside `Visuals` so it never becomes debris), optional
## `Visuals/Shell` (rolls with movement).

## Radius of the ring mesh in the scene (m); scaled to the blast radius.
const RING_MESH_RADIUS: float = 1.0
## Radius of the rolling shell (m), for the roll speed.
const SHELL_RADIUS: float = 0.45

@onready var _ring: MeshInstance3D = $WarningRing
@onready var _shell: Node3D = get_node_or_null("Visuals/Shell")


func _ready() -> void:
	super()
	_ring.visible = false
	health.died.connect(func(_info: DamageInfo) -> void: _ring.visible = false)


func _process(delta: float) -> void:
	if _shell == null or health.is_dead():
		return
	var speed: float = Vector2(velocity.x, velocity.z).length()
	_shell.rotate_object_local(Vector3.RIGHT, -speed * delta / SHELL_RADIUS)


## Arms: flash the core and show the blast radius on the ground.
func telegraph_attack(windup: float) -> void:
	super(windup)
	var size: float = data.death_blast_radius / RING_MESH_RADIUS
	_ring.visible = true
	_ring.scale = Vector3(size * 0.3, 1.0, size * 0.3)
	var tween: Tween = create_tween()
	tween.tween_property(_ring, "scale", Vector3(size, 1.0, size), windup * 0.7)


## The blast reaches as far as its radius (plus the player's hurtbox).
func get_threat_reach() -> float:
	return maxf(data.death_blast_radius + THREAT_MARGIN, super())


## Self-destructs; the blast comes from dying (BaseEnemy death blast).
func perform_attack() -> void:
	attacked.emit()
	var info: DamageInfo = DamageInfo.create(1.0e6, DamageInfo.Type.KINETIC, self, global_position)
	health.invulnerable = false
	health.apply_damage(info)
