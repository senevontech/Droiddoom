class_name EnemyState
extends State
## Base for BaseEnemy states (P1-08). States only decide; BaseEnemy does the
## moving, path requests, line-of-sight rays and attacks. `update(delta)` runs
## at the enemy's AI LOD rate and `delta` is the time since the last think.


## The enemy this state belongs to.
func enemy() -> BaseEnemy:
	return actor as BaseEnemy
