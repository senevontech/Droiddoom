extends GutTest
## P1-10: the Wave Director's point-budget maths (GDD §7.3).

const SWARMER: PackedScene = preload("res://actors/enemies/swarmer/swarmer.tscn")
const GUNNER: PackedScene = preload("res://actors/enemies/gunner/gunner.tscn")


func test_roster_spends_the_budget_exactly_when_cheap_picks_exist() -> void:
	var rng: RandomNumberGenerator = _rng()
	var pool: Array[EnemyEntry] = [_entry(SWARMER, 1, 1.0), _entry(GUNNER, 3, 1.0)]
	for budget: int in [1, 5, 12, 30]:
		var roster: Array[PackedScene] = WaveDirector.build_roster(pool, budget, rng)
		var spent: int = 0
		for scene: PackedScene in roster:
			spent += 1 if scene == SWARMER else 3
		assert_eq(spent, budget, "budget %d spent exactly" % budget)


func test_roster_never_picks_what_it_cannot_afford() -> void:
	var pool: Array[EnemyEntry] = [_entry(GUNNER, 3, 1.0)]
	var roster: Array[PackedScene] = WaveDirector.build_roster(pool, 8, _rng())
	assert_eq(roster.size(), 2, "two gunners, 2 points left unspent")


func test_weights_shape_the_mix() -> void:
	var pool: Array[EnemyEntry] = [_entry(SWARMER, 1, 9.0), _entry(GUNNER, 1, 1.0)]
	var roster: Array[PackedScene] = WaveDirector.build_roster(pool, 1000, _rng())
	var gunners: int = roster.count(GUNNER)
	assert_between(gunners, 60, 140, "about 10% gunners")


func test_endless_budget_grows_past_the_last_wave() -> void:
	var director: WaveDirector = WaveDirector.new()
	director.wave_set = load("res://data/waves/waves_arena.tres")
	var last: int = director.wave_set.waves.size()
	var last_budget: int = director.get_budget(last)
	assert_gt(director.get_budget(last + 1), last_budget)
	assert_gt(director.get_budget(last + 3), director.get_budget(last + 2))
	director.free()


func _entry(scene: PackedScene, cost: int, weight: float) -> EnemyEntry:
	var entry: EnemyEntry = EnemyEntry.new()
	entry.scene = scene
	entry.cost = cost
	entry.weight = weight
	return entry


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 7
	return rng
